#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Install Docker first."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon not reachable. Start Docker."
  exit 1
fi

read -rp "Image name (repository) [brimdor/comfyui]: " IMAGE
IMAGE="${IMAGE:-brimdor/comfyui}"

read -rp "Tag [cuda]: " TAG
TAG="${TAG:-cuda}"

read -rp "Use PyTorch nightly (cu129)? [y/N]: " NIGHTLY
NIGHTLY="${NIGHTLY:-N}"

read -rp "Build without cache? [y/N]: " NOCACHE
NOCACHE="${NOCACHE:-N}"

BUILD_ARGS=()
if [[ "$NIGHTLY" =~ ^[Yy]$ ]]; then
  BUILD_ARGS+=(--build-arg TORCH_NIGHTLY=true)
fi

NO_CACHE_FLAG=()
if [[ "$NOCACHE" =~ ^[Yy]$ ]]; then
  NO_CACHE_FLAG+=(--no-cache)
fi

FULL_TAG="${IMAGE}:${TAG}"

echo "Building ${FULL_TAG} ..."
DOCKER_BUILDKIT=1 docker build \
  "${NO_CACHE_FLAG[@]}" \
  "${BUILD_ARGS[@]}" \
  -t "${FULL_TAG}" \
  -f "${ROOT_DIR}/Dockerfile" \
  "${ROOT_DIR}"

echo "Built ${FULL_TAG}"
echo "Run (with NVIDIA GPU) example:"
echo "  docker run --gpus all -p 8188:8188 \\"
echo "    -v \"${ROOT_DIR}/models:/app/models\" \\"
echo "    -v \"${ROOT_DIR}/input:/app/input\" \\"
echo "    -v \"${ROOT_DIR}/output:/app/output\" \\"
echo "    ${FULL_TAG}"