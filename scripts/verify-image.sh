#!/usr/bin/env bash
# Require all published evidence from this repository's authorized workflow.

set -euo pipefail

readonly OIDC_ISSUER='https://token.actions.githubusercontent.com'

usage() {
  echo "Usage: $0 <image@sha256:digest> <github-owner/repository>" >&2
}

fail_verification() {
  echo "ERROR: $1" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

readonly IMAGE_REF="$1"
readonly EXPECTED_REPOSITORY="$2"
readonly COSIGN_BIN="${COSIGN_BIN:-cosign}"

if [[ ! "$IMAGE_REF" =~ ^[^[:space:]@]+@sha256:[0-9a-f]{64}$ ]]; then
  echo "ERROR: image must include a complete sha256 digest" >&2
  exit 2
fi

if [[ ! "$EXPECTED_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "ERROR: expected repository must be owner/name" >&2
  exit 2
fi

if [[ "$COSIGN_BIN" == */* ]]; then
  if [[ ! -f "$COSIGN_BIN" ]]; then
    echo "ERROR: cosign is required" >&2
    exit 2
  fi
elif ! command -v "$COSIGN_BIN" >/dev/null 2>&1; then
  echo "ERROR: cosign is required" >&2
  exit 2
fi

# GitHub repository names can contain dots; escape those before building the
# anchored certificate identity. The workflow and allowed refs are exact.
escaped_repository=${EXPECTED_REPOSITORY//./\\.}
readonly IDENTITY_REGEX="^https://github\\.com/${escaped_repository}/\\.github/workflows/supply-chain\\.yml@refs/(heads/main|tags/v[^/]+)$"

common_args=(
  --certificate-identity-regexp "$IDENTITY_REGEX"
  --certificate-oidc-issuer "$OIDC_ISSUER"
)

echo "Verifying signature for $IMAGE_REF"
if ! "$COSIGN_BIN" verify "$IMAGE_REF" "${common_args[@]}" >/dev/null; then
  fail_verification "required image signature is missing or has the wrong identity"
fi

echo "Verifying signed SPDX SBOM attestation"
if ! "$COSIGN_BIN" verify-attestation "$IMAGE_REF" \
  --type spdxjson "${common_args[@]}" >/dev/null; then
  fail_verification "required SPDX SBOM attestation is missing or has the wrong identity"
fi

echo "Verifying signed SLSA provenance attestation"
if ! "$COSIGN_BIN" verify-attestation "$IMAGE_REF" \
  --type slsaprovenance "${common_args[@]}" >/dev/null 2>&1 && \
   ! "$COSIGN_BIN" verify-attestation "$IMAGE_REF" \
  --type https://slsa.dev/provenance/v1 "${common_args[@]}" >/dev/null; then
  fail_verification "required build provenance is missing or has the wrong identity"
fi

echo "PASS: signature, SPDX SBOM, and provenance match $EXPECTED_REPOSITORY"
