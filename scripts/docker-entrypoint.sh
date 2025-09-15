#!/usr/bin/env bash
set -euo pipefail

TORCH_INDEX_URL="${TORCH_INDEX_URL:-https://download.pytorch.org/whl/cu129}"
TORCH_NIGHTLY="${TORCH_NIGHTLY:-false}"
WORKSPACE="${WORKSPACE:-/comfyui}"

## Ensure python user-base bins are on PATH and set pip root behaviour
# Add both root and comfy user's user-base bin dirs so scripts installed by
# pip are immediately available regardless of whether we run installs as
# root or as the comfy user.
ROOT_USER_BASE="$(python -m site --user-base 2>/dev/null || echo '/root/.local')"
COMFY_USER_BASE="/home/comfy/.local"
export PATH="${ROOT_USER_BASE}/bin:${COMFY_USER_BASE}/bin:${PATH}"

# Suppress the scary pip-as-root warning (we still prefer doing installs as
# the comfy user when possible). Also disable pip version check to reduce
# noise during container startup.
export PIP_ROOT_USER_ACTION=ignore
export PIP_DISABLE_PIP_VERSION_CHECK=1

run_as_comfy() {
  # Try to run the given command as the 'comfy' user using any available
  # helper (gosu, su-exec, runuser, sudo, su). Returns 0 on success.
  if command -v gosu >/dev/null 2>&1; then
    gosu comfy "$@"
    return $?
  fi
  if command -v su-exec >/dev/null 2>&1; then
    su-exec comfy "$@"
    return $?
  fi
  if command -v runuser >/dev/null 2>&1; then
    runuser -u comfy -- "$@"
    return $?
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo -u comfy "$@"
    return $?
  fi
  if command -v su >/dev/null 2>&1; then
    # last-resort: use su -c (note: needs careful quoting)
    su - comfy -c "$(printf '%q ' "$@")"
    return $?
  fi
  return 1
}

install_deps() {
  # Install packages into the user's site-packages. Prefer to run the
  # installers as the non-root 'comfy' user when possible; otherwise install
  # as root and fix permissions afterwards.
  echo "[entrypoint] Preparing to install Python packages (user site)"

  if run_as_comfy true 2>/dev/null; then
    echo "[entrypoint] Running pip installs as 'comfy' user"
    run_as_comfy python -m pip install --upgrade --user pip setuptools wheel

    if [ -n "${TORCH_INDEX_URL}" ]; then
      if [ "${TORCH_NIGHTLY}" = "true" ]; then
        run_as_comfy python -m pip install --user --pre torch torchvision torchaudio --index-url "${TORCH_INDEX_URL}"
      else
        run_as_comfy python -m pip install --user torch torchvision torchaudio --extra-index-url "${TORCH_INDEX_URL}"
      fi
    else
      run_as_comfy python -m pip install --user torch torchvision torchaudio
    fi

    if [ -f /app/requirements.txt ]; then
      grep -v -E '^(torch|torchvision|torchaudio)(==|~=|>=|<=|<|>|[[:space:]]|$)' /app/requirements.txt > /tmp/requirements.no-torch.txt || true
      if [ -s /tmp/requirements.no-torch.txt ]; then
        run_as_comfy python -m pip install --user -r /tmp/requirements.no-torch.txt
      fi
    fi

  else
    echo "[entrypoint] Could not find a helper to drop privileges; installing as root and fixing permissions"
    python -m pip install --upgrade --user pip setuptools wheel

    if [ -n "${TORCH_INDEX_URL}" ]; then
      if [ "${TORCH_NIGHTLY}" = "true" ]; then
        python -m pip install --user --pre torch torchvision torchaudio --index-url "${TORCH_INDEX_URL}"
      else
        python -m pip install --user torch torchvision torchaudio --extra-index-url "${TORCH_INDEX_URL}"
      fi
    else
      python -m pip install --user torch torchvision torchaudio
    fi

    if [ -f /app/requirements.txt ]; then
      grep -v -E '^(torch|torchvision|torchaudio)(==|~=|>=|<=|<|>|[[:space:]]|$)' /app/requirements.txt > /tmp/requirements.no-torch.txt || true
      if [ -s /tmp/requirements.no-torch.txt ]; then
        python -m pip install --user -r /tmp/requirements.no-torch.txt
      fi
    fi

    # Fix permissions so comfy user can use installed scripts and packages
    if [ -d "${ROOT_USER_BASE}" ]; then
      chown -R comfy:comfy "${ROOT_USER_BASE}" || true
    fi
    mkdir -p "${COMFY_USER_BASE}"
    chown -R comfy:comfy "${COMFY_USER_BASE}" || true
  fi
}

mkdir -p "${WORKSPACE}"
chown -R comfy:comfy "${WORKSPACE}" || true

# No comfy-cli path: perform pip installs directly and start the app.
if [ ! -f "${WORKSPACE}/.comfy_installed" ]; then
  echo "[entrypoint] Installing dependencies via pip into user site (this may take a while)"
  install_deps
  touch "${WORKSPACE}/.comfy_installed"
else
  echo "[entrypoint] Dependencies already installed (marker present)"
fi

echo "[entrypoint] Starting ComfyUI using system python"
python -V || true
# Ensure any user-site site-packages (root or comfy) are on PYTHONPATH so
# imports succeed even if packages were installed into /root/.local earlier.
for d in /root/.local/lib/python*/site-packages /home/comfy/.local/lib/python*/site-packages; do
  if [ -d "$d" ]; then
    PYTHONPATH="${PYTHONPATH:+${PYTHONPATH}:}$d"
  fi
done
export PYTHONPATH
echo "[entrypoint] PYTHONPATH=$PYTHONPATH"
exec python -u /app/main.py "$@"