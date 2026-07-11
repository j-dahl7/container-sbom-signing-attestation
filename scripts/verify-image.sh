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
# Example: ./scripts/verify-image.sh ghcr.io/j-dahl7/container-sbom-signing-attestation@sha256:abc123...
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
CERTIFICATE_IDENTITY_REGEXP='^https://github\.com/j-dahl7/container-sbom-signing-attestation/\.github/workflows/supply-chain\.yml@refs/(heads/main|tags/v[^/]+)$'

# Check for required tools
check_tools() {
    local missing=()

    command -v cosign >/dev/null 2>&1 || missing+=("cosign")
    command -v gh >/dev/null 2>&1 || missing+=("gh")
    command -v jq >/dev/null 2>&1 || missing+=("jq")

    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing required tools: ${missing[*]}${NC}"
        echo ""
        echo "Install with:"
        echo "  brew install cosign gh jq"
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

    local output
    if output=$(cosign verify "$IMAGE_REF" \
        --certificate-identity-regexp="$CERTIFICATE_IDENTITY_REGEXP" \
        --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
        2>&1); then
        printf '%s\n' "$output" | sed -n '1,20p'
        echo -e "${GREEN}Signature verified!${NC}"
    else
        printf '%s\n' "$output" | sed -n '1,20p' >&2
        echo -e "${RED}Signature verification failed!${NC}"
        return 1
    fi
}

# Verify SBOM attestation
verify_sbom() {
    echo ""
    echo -e "${BLUE}[2/4] Verifying SBOM attestation...${NC}"

    local output
    if output=$(cosign verify-attestation "$IMAGE_REF" \
        --type spdxjson \
        --certificate-identity-regexp="$CERTIFICATE_IDENTITY_REGEXP" \
        --certificate-oidc-issuer='https://token.actions.githubusercontent.com' \
        2>&1); then
        printf '%s\n' "$output" | sed -n '1,5p'
        echo -e "${GREEN}SBOM attestation verified!${NC}"
    else
        printf '%s\n' "$output" | sed -n '1,20p' >&2
        echo -e "${RED}Required SBOM attestation verification failed!${NC}"
        return 1
    fi
}

# Extract and display SBOM summary
show_sbom_summary() {
    echo ""
    echo -e "${BLUE}[3/4] Extracting SBOM contents...${NC}"

    local sbom_json
    sbom_json=$(cosign verify-attestation "$IMAGE_REF" \
        --type spdxjson \
        --certificate-identity-regexp="$CERTIFICATE_IDENTITY_REGEXP" \
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

    local output
    if output=$(gh attestation verify "oci://$IMAGE_REF" \
        --repo 'j-dahl7/container-sbom-signing-attestation' \
        --cert-identity-regex "$CERTIFICATE_IDENTITY_REGEXP" \
        --predicate-type 'https://slsa.dev/provenance/v1' \
        2>&1); then
        printf '%s\n' "$output" | sed -n '1,20p'
        echo -e "${GREEN}GitHub build provenance verified!${NC}"
    else
        printf '%s\n' "$output" | sed -n '1,20p' >&2
        echo -e "${RED}Required GitHub build provenance verification failed!${NC}"
        echo "Authenticate gh and the registry before retrying (gh auth login; docker login ghcr.io)." >&2
        return 1
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Supply Chain Verification Complete (all required checks passed)${NC}"
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
        echo "  $0 ghcr.io/j-dahl7/container-sbom-signing-attestation@sha256:abc123..."
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
