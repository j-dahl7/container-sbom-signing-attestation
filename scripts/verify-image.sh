#!/usr/bin/env bash
# Require all published evidence from this repository's authorized workflow.

set -euo pipefail

readonly OIDC_ISSUER='https://token.actions.githubusercontent.com'
readonly MAX_VERIFY_ATTEMPTS=5
readonly MAX_RETRY_DELAY_SECONDS=30
readonly INITIAL_RETRY_DELAY_SECONDS="${VERIFY_RETRY_DELAY_SECONDS:-2}"

usage() {
  echo "Usage: $0 <image@sha256:digest> <github-owner/repository>" >&2
}

fail_verification() {
  echo "ERROR: $1" >&2
  exit 1
}

if [[ ! "$INITIAL_RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] ||
   (( INITIAL_RETRY_DELAY_SECONDS > 30 )); then
  echo "ERROR: VERIFY_RETRY_DELAY_SECONDS must be an integer from 0 to 30" >&2
  exit 2
fi

# Registry signatures and attestations can become visible shortly after the
# image manifest. Retry only the read-only verification calls, with a bounded
# exponential delay; invalid or persistently missing evidence still fails.
verify_with_retry() {
  local description="$1"
  shift
  local attempt=1
  local delay_seconds="$INITIAL_RETRY_DELAY_SECONDS"

  while (( attempt <= MAX_VERIFY_ATTEMPTS )); do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    if (( attempt == MAX_VERIFY_ATTEMPTS )); then
      return 1
    fi
    echo "Waiting for $description: attempt $attempt/$MAX_VERIFY_ATTEMPTS failed; retrying in ${delay_seconds}s" >&2
    sleep "$delay_seconds"
    delay_seconds=$((delay_seconds * 2))
    if (( delay_seconds > MAX_RETRY_DELAY_SECONDS )); then
      delay_seconds=$MAX_RETRY_DELAY_SECONDS
    fi
    attempt=$((attempt + 1))
  done
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

verify_signature() {
  "$COSIGN_BIN" verify "$IMAGE_REF" "${common_args[@]}"
}

verify_spdx_sbom() {
  "$COSIGN_BIN" verify-attestation "$IMAGE_REF" \
    --type spdxjson "${common_args[@]}"
}

verify_provenance() {
  "$COSIGN_BIN" verify-attestation "$IMAGE_REF" \
    --type slsaprovenance "${common_args[@]}" ||
    "$COSIGN_BIN" verify-attestation "$IMAGE_REF" \
      --type https://slsa.dev/provenance/v1 "${common_args[@]}"
}

echo "Verifying signature for $IMAGE_REF"
if ! verify_with_retry "image signature" verify_signature; then
  fail_verification "required image signature is missing or has the wrong identity"
fi

echo "Verifying signed SPDX SBOM attestation"
if ! verify_with_retry "SPDX SBOM attestation" verify_spdx_sbom; then
  fail_verification "required SPDX SBOM attestation is missing or has the wrong identity"
fi

echo "Verifying signed SLSA provenance attestation"
if ! verify_with_retry "SLSA provenance attestation" verify_provenance; then
  fail_verification "required build provenance is missing or has the wrong identity"
fi

echo "PASS: signature, SPDX SBOM, and provenance match $EXPECTED_REPOSITORY"
