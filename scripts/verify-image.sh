#!/bin/bash
# =============================================================================
# Supply Chain Verification Script
# =============================================================================
# This script verifies the supply chain security artifacts for a container image:
# - Cosign signature (keyless/Sigstore)
# - SBOM attestation
# - Build provenance
#
# Usage: ./scripts/verify-image.sh <image-with-digest>
# Example: ./scripts/verify-image.sh ghcr.io/j-dahl7/supply-chain-lab@sha256:abc123...
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check for required tools
check_tools() {
    local missing=()

    command -v cosign >/dev/null 2>&1 || missing+=("cosign")
    command -v jq >/dev/null 2>&1 || missing+=("jq")

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo ""
        echo "Install with:"
        echo "  brew install cosign jq"
        echo "  # or"
        echo "  go install github.com/sigstore/cosign/v2/cmd/cosign@latest"
        exit 1
    fi
}

# Parse image reference
parse_image() {
    local image="$1"

    if [[ ! "$image" =~ @ ]]; then
        echo -e "${RED}Error: Image must include digest (image@sha256:...)${NC}"
        echo "Use: docker inspect <image> --format='{{.RepoDigests}}'"
        exit 1
    fi

    IMAGE_REF="$image"
    IMAGE_REPO="${image%%@*}"
    IMAGE_DIGEST="${image##*@}"
}

# Verify signature
verify_signature() {
    echo -e "${BLUE}[1/4] Verifying Cosign signature...${NC}"

    if cosign verify "$IMAGE_REF" \
        --certificate-identity-regexp='https://github.com/.*' \
        --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
        2>&1 | head -20; then
        echo -e "${GREEN}Signature verified!${NC}"
    else
        echo -e "${RED}Signature verification failed!${NC}"
        return 1
    fi
}

# Verify SBOM attestation
verify_sbom() {
    echo ""
    echo -e "${BLUE}[2/4] Verifying SBOM attestation...${NC}"

    if cosign verify-attestation "$IMAGE_REF" \
        --type spdxjson \
        --certificate-identity-regexp='https://github.com/.*' \
        --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
        2>&1 | head -5; then
        echo -e "${GREEN}SBOM attestation verified!${NC}"
    else
        echo -e "${YELLOW}No SBOM attestation found (optional)${NC}"
    fi
}

# Extract and display SBOM summary
show_sbom_summary() {
    echo ""
    echo -e "${BLUE}[3/4] Extracting SBOM contents...${NC}"

    local sbom_json
    sbom_json=$(cosign verify-attestation "$IMAGE_REF" \
        --type spdxjson \
        --certificate-identity-regexp='https://github.com/.*' \
        --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
        2>/dev/null | jq -r '.payload' | base64 -d 2>/dev/null || echo "{}")

    if [ "$sbom_json" != "{}" ]; then
        echo "SBOM Format: $(echo "$sbom_json" | jq -r '.predicateType // "unknown"')"
        echo "Package Count: $(echo "$sbom_json" | jq -r '.predicate.packages | length // 0')"
        echo ""
        echo "Top 5 packages:"
        echo "$sbom_json" | jq -r '.predicate.packages[:5][] | "  - \(.name)@\(.versionInfo // "unknown")"' 2>/dev/null || echo "  (Unable to parse packages)"
    else
        echo -e "${YELLOW}No SBOM data available${NC}"
    fi
}

# Check for provenance
check_provenance() {
    echo ""
    echo -e "${BLUE}[4/4] Checking build provenance...${NC}"

    # Try to get provenance attestation
    if cosign verify-attestation "$IMAGE_REF" \
        --type slsaprovenance \
        --certificate-identity-regexp='https://github.com/.*' \
        --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
        2>&1 | head -5; then
        echo -e "${GREEN}Build provenance attestation found!${NC}"
    else
        # Try GitHub's native attestation format
        if cosign verify-attestation "$IMAGE_REF" \
            --type https://slsa.dev/provenance/v1 \
            --certificate-identity-regexp='https://github.com/.*' \
            --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
            2>&1 | head -5; then
            echo -e "${GREEN}SLSA v1 provenance found!${NC}"
        else
            echo -e "${YELLOW}No explicit provenance attestation (may be embedded in image)${NC}"
        fi
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Supply Chain Verification Complete${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Image: $IMAGE_REPO"
    echo "Digest: $IMAGE_DIGEST"
    echo ""
    echo "To pull this verified image:"
    echo "  docker pull $IMAGE_REF"
}

# Main
main() {
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <image@digest>"
        echo ""
        echo "Example:"
        echo "  $0 ghcr.io/j-dahl7/supply-chain-lab@sha256:abc123..."
        exit 1
    fi

    check_tools
    parse_image "$1"

    echo "=========================================="
    echo "Supply Chain Verification"
    echo "=========================================="
    echo "Image: $IMAGE_REF"
    echo ""

    verify_signature
    verify_sbom
    show_sbom_summary
    check_provenance
    print_summary
}

main "$@"
