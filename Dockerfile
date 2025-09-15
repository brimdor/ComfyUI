# Slim runtime image: defers pip installs to container start
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    TORCH_INDEX_URL=https://download.pytorch.org/whl/cu129 \
    TORCH_NIGHTLY=false

# Minimal runtime libs; include git so comfy-cli (gitpython) can operate
RUN apt-get update && apt-get install -y --no-install-recommends \
            git libgl1 libglib2.0-0 libsndfile1 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install gosu so we can drop privileges in the entrypoint (small, widely used helper)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends dirmngr gnupg ca-certificates wget; \
    rm -rf /var/lib/apt/lists/*; \
    export GOSU_VERSION="1.16"; \
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
    wget -O /tmp/gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${dpkgArch}"; \
    wget -O /tmp/gosu.asc "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${dpkgArch}.asc"; \
    install -m 0755 /tmp/gosu /usr/local/bin/gosu; \
    rm -f /tmp/gosu /tmp/gosu.asc; \
    gosu --version || true

WORKDIR /app

# Non-root user
RUN useradd -m -u 1000 -s /bin/bash comfy

# Prepare workspace directories (workspace for ComfyUI and user-local pip dir)
ENV WORKSPACE=/comfyui
RUN mkdir -p /app /comfyui /home/comfy/.local /home/comfy/.cache \
    && chown -R comfy:comfy /comfyui /home/comfy/.local /home/comfy/.cache /app

# Copy application source and entrypoint (entrypoint will perform installs at runtime)
COPY --chown=comfy:comfy . /app
COPY --chown=comfy:comfy scripts/docker-entrypoint.sh /app/scripts/docker-entrypoint.sh
RUN chmod +x /app/scripts/docker-entrypoint.sh

# Persist models, IO, and venv so installs only happen once
VOLUME ["/app/models", "/app/input", "/app/output", "/comfyui", "/home/comfy/.local", "/home/comfy/.cache"]

EXPOSE 8188
USER comfy

ENTRYPOINT ["/app/scripts/docker-entrypoint.sh"]
CMD ["--listen", "0.0.0.0", "--port", "8188"]