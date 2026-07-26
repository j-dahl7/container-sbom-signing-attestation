#!/usr/bin/env bash
# Build, scan, inventory, and smoke-test locally without publishing.

set -euo pipefail

readonly IMAGE_NAME="supply-chain-demo"
readonly IMAGE_TAG="local"

missing=()
for tool in docker trivy syft curl; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [[ ${#missing[@]} -gt 0 ]]; then
  echo "ERROR: missing required tools: ${missing[*]}" >&2
  exit 2
fi

container_id=""
cleanup() {
  if [[ -n "$container_id" ]]; then
    docker rm -f "$container_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "[1/5] Enforcing immutable references"
bash scripts/check-pinned-refs.sh

echo "[2/5] Building the local image"
docker build \
  --build-arg VERSION=local \
  --build-arg BUILD_TIME="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
  --build-arg GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" \
  .

echo "[3/5] Failing on critical vulnerabilities"
trivy image \
  --exit-code 1 \
  --ignore-unfixed \
  --severity CRITICAL \
  "${IMAGE_NAME}:${IMAGE_TAG}"

echo "[4/5] Generating SPDX and CycloneDX SBOMs"
syft "${IMAGE_NAME}:${IMAGE_TAG}" --output spdx-json=sbom.spdx.json
syft "${IMAGE_NAME}:${IMAGE_TAG}" --output cyclonedx-json=sbom.cdx.json

echo "[5/5] Running a fail-closed health check"
container_id=$(docker run -d -p 127.0.0.1::8080 "${IMAGE_NAME}:${IMAGE_TAG}")
published_port=$(docker port "$container_id" 8080/tcp | awk -F: 'NR == 1 {print $NF}')
if [[ -z "$published_port" ]]; then
  echo "ERROR: Docker did not publish the health port" >&2
  exit 1
fi

healthy=false
for _ in 1 2 3 4 5; do
  if curl --fail --silent --show-error "http://127.0.0.1:${published_port}/health" >/dev/null; then
    healthy=true
    break
  fi
  sleep 1
done
if [[ "$healthy" != true ]]; then
  echo "ERROR: container health endpoint did not become ready" >&2
  exit 1
fi

echo "PASS: local image built, scanned, inventoried, and health-checked"
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "SBOMs: sbom.spdx.json, sbom.cdx.json"
