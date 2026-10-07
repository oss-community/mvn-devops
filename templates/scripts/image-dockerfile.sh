#!/usr/bin/env bash
# Pipeline step: builds the image from the project's Dockerfile and pushes it.
# Needs Docker where the pipeline runs.  Usage: image-dockerfile.sh [module]
# The Dockerfile of the module is used when it has one, else the root's.
set -euo pipefail

module=${1:-.}
tag=$(git rev-parse --short=12 HEAD)
dockerfile=Dockerfile
[[ -f "$module/Dockerfile" ]] && dockerfile="$module/Dockerfile"

if [[ -n ${IMAGE_REGISTRY_PASSWORD:-} ]]; then
  printf '%s' "$IMAGE_REGISTRY_PASSWORD" \
    | docker login --username "$IMAGE_REGISTRY_USERNAME" --password-stdin "${IMAGE_REPOSITORY%%/*}"
fi
docker build --file "$dockerfile" --tag "$IMAGE_REPOSITORY:$tag" --tag "$IMAGE_REPOSITORY:latest" "$module"
docker push "$IMAGE_REPOSITORY:$tag"
docker push "$IMAGE_REPOSITORY:latest"
