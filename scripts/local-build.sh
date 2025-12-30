#!/bin/bash
# =============================================================================
# Local Build and Scan Script
# =============================================================================
# Build and scan the container image locally without pushing.
# Great for testing before CI/CD.
#
# Usage: ./scripts/local-build.sh
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

IMAGE_NAME="supply-chain-demo"
IMAGE_TAG="local"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Local Build & Scan${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Build
echo -e "${BLUE}[1/4] Building image...${NC}"
docker build \
    --build-arg VERSION=local \
    --build-arg BUILD_TIME="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    --build-arg GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    .

echo -e "${GREEN}Build complete!${NC}"
echo ""

# Scan with Trivy
echo -e "${BLUE}[2/4] Scanning for vulnerabilities (Trivy)...${NC}"
if command -v trivy >/dev/null 2>&1; then
    trivy image --severity HIGH,CRITICAL "${IMAGE_NAME}:${IMAGE_TAG}"
else
    echo -e "${YELLOW}Trivy not installed. Install with: brew install trivy${NC}"
fi
echo ""

# Generate SBOM with Syft
echo -e "${BLUE}[3/4] Generating SBOM (Syft)...${NC}"
if command -v syft >/dev/null 2>&1; then
    syft "${IMAGE_NAME}:${IMAGE_TAG}" -o table
    echo ""
    echo "Generating SBOM files..."
    syft "${IMAGE_NAME}:${IMAGE_TAG}" -o spdx-json > sbom.spdx.json
    syft "${IMAGE_NAME}:${IMAGE_TAG}" -o cyclonedx-json > sbom.cdx.json
    echo -e "${GREEN}SBOMs saved: sbom.spdx.json, sbom.cdx.json${NC}"
else
    echo -e "${YELLOW}Syft not installed. Install with: brew install syft${NC}"
fi
echo ""

# Test run
echo -e "${BLUE}[4/4] Testing container...${NC}"
CONTAINER_ID=$(docker run -d -p 8080:8080 "${IMAGE_NAME}:${IMAGE_TAG}")
sleep 2

if curl -s http://localhost:8080/health | jq .; then
    echo -e "${GREEN}Container is healthy!${NC}"
else
    echo -e "${RED}Container health check failed${NC}"
fi

docker stop "$CONTAINER_ID" >/dev/null
docker rm "$CONTAINER_ID" >/dev/null

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Local Build Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Image: ${IMAGE_NAME}:${IMAGE_TAG}"
echo ""
echo "Next steps:"
echo "  1. Review vulnerability scan results above"
echo "  2. Check SBOM files: sbom.spdx.json, sbom.cdx.json"
echo "  3. Push to trigger CI/CD pipeline"
