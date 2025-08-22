# ComfyUI Dockerfile (Python 3.12 on Debian bookworm-slim)
# - Simpler base matching repo's Python 3.12 recommendation
# - Defaults to NVIDIA GPU via PyTorch cu129 wheels; supports CPU fallback
# - Uses non-root user and mounts for models/input/output
# - Exposes port 8188 and binds to 0.0.0.0

FROM python:3.12-slim-bookworm

# ----- Build args to control PyTorch variant -----
# Set TORCH_INDEX_URL="" to build a CPU-only image.
ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu129
# Change to nightly if desired (optional); when using nightly, prefer --index-url over --extra-index-url
ARG TORCH_NIGHTLY=false

# Disable interactive APT, speed up pip and logs unbuffered
ENV DEBIAN_FRONTEND=noninteractive \
  PIP_NO_CACHE_DIR=1 \
  PYTHONUNBUFFERED=1

# ----- System deps -----
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ffmpeg \
    libgl1 \
    libglib2.0-0 \
    libsndfile1 \
    curl \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

# Upgrade pip tooling
RUN pip install --upgrade pip setuptools wheel

WORKDIR /app

# Copy and pre-install PyTorch stack with the chosen variant first to avoid CPU fallback
COPY requirements.txt /app/requirements.txt

# Install torch/torchvision/torchaudio first with the right index, then the rest
# We strip torch family from requirements to prevent pip from overriding our install.
RUN set -eux; \
    if [ -n "$TORCH_INDEX_URL" ]; then \
        if [ "$TORCH_NIGHTLY" = "true" ]; then \
            pip install --pre torch torchvision torchaudio --index-url "$TORCH_INDEX_URL"; \
        else \
            pip install torch torchvision torchaudio --extra-index-url "$TORCH_INDEX_URL"; \
        fi; \
    else \
        pip install torch torchvision torchaudio; \
    fi; \
    grep -v -E '^(torch|torchvision|torchaudio)(==|~=|>=|\s|$)' /app/requirements.txt > /tmp/requirements.no-torch.txt; \
    pip install -r /tmp/requirements.no-torch.txt

# Copy the rest of the source
COPY . /app

# Create a non-root user for safety
RUN useradd -m -u 1000 -s /bin/bash comfy \
  && chown -R comfy:comfy /app

# Prepare common mount points
VOLUME ["/app/models", "/app/input", "/app/output", "/home/comfy/.cache"]

# Default port
EXPOSE 8188

# Simple healthcheck: HTTP root should respond once the server is up
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=5 \
  CMD curl -fsS http://127.0.0.1:8188/ || exit 1

USER comfy

# Entry: pass extra args at docker run time to customize behavior
# Common additions:
#   --listen 0.0.0.0  --port 8188
#   --preview-method auto|taesd
#   --front-end-version Comfy-Org/ComfyUI_frontend@latest
ENTRYPOINT ["python", "-u", "/app/main.py"]
CMD ["--listen", "0.0.0.0", "--port", "8188"]

# Notes for GPU use on host (not enforced here):
# - For NVIDIA GPUs, ensure the host has the NVIDIA driver and use the NVIDIA Container Toolkit.
# - Run with:  docker run --gpus all ...
