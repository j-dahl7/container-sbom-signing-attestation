<p align="center">
  <img src="https://nineliveszerotrust.com/images/blog/supply-chain/pipeline-hero.png" alt="Container Supply Chain Security Pipeline" width="800">
</p>

# Container SBOM, Signing & Attestation Lab

> **Companion repo for the blog post: [Secure Your Container Supply Chain: SBOM, Signing & Attestation with GitHub Actions](https://nineliveszerotrust.com/blog/container-sbom-signing-attestation/)**

This hands-on lab demonstrates a complete container supply chain security pipeline using **zero secrets** - everything is keyless via OIDC and Sigstore.

## What You'll Learn

- **Build** hardened container images (distroless, multi-stage)
- **Scan** for vulnerabilities with Trivy
- **Generate** Software Bill of Materials (SBOM) with Syft
- **Sign** images with Cosign (keyless via Sigstore)
- **Attest** build provenance (SLSA compliance)
- **Verify** the entire supply chain as a consumer

## The Zero-Trust Pipeline

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    GitHub Actions Pipeline                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────────┐   │
│  │  Build   │───▶│   Scan   │───▶│   SBOM   │───▶│  Sign & Attest   │   │
│  │ (Docker) │    │ (Trivy)  │    │  (Syft)  │    │ (Cosign/SLSA)    │   │
│  └──────────┘    └──────────┘    └──────────┘    └──────────────────┘   │
│       │                                                    │             │
│       │              OIDC (No Secrets!)                    │             │
│       └───────────────────┬────────────────────────────────┘             │
│                           ▼                                              │
│                    ┌──────────────┐                                      │
│                    │    GHCR      │                                      │
│                    │  (Registry)  │                                      │
│                    └──────────────┘                                      │
│                           │                                              │
│                           ▼                                              │
│              Image + Signature + SBOM + Provenance                       │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## Zero Secrets Architecture

| Component | How It Authenticates | Secret Required? |
|-----------|---------------------|------------------|
| GitHub → GHCR | `GITHUB_TOKEN` (automatic) | No |
| Cosign → Sigstore | OIDC to Fulcio | No |
| Build Provenance | GitHub Attestations | No |

**No AWS/Azure/GCP credentials needed!** The entire pipeline runs with GitHub's built-in OIDC.

---

## Quick Start

### Prerequisites

```bash
# Install tools (macOS)
brew install cosign syft trivy jq docker

# Or install individually
go install github.com/sigstore/cosign/v2/cmd/cosign@latest
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
```

### Local Build & Scan

```bash
# Clone the repo
git clone https://github.com/j-dahl7/container-sbom-signing-attestation.git
cd container-sbom-signing-attestation

# Build and scan locally
./scripts/local-build.sh
```

### Verify a Published Image

```bash
# Get the image digest from GHCR
IMAGE="ghcr.io/j-dahl7/supply-chain-lab@sha256:..."

# Run verification
./scripts/verify-image.sh $IMAGE
```

---

## Lab Structure

```
container-sbom-signing-attestation/
├── .github/workflows/
│   └── supply-chain.yml      # Full CI/CD pipeline
├── app/
│   ├── main.go               # Simple Go app
│   └── go.mod
├── scripts/
│   ├── local-build.sh        # Build & scan locally
│   └── verify-image.sh       # Verify supply chain
├── Dockerfile                # Hardened multi-stage build
└── README.md
```

---

## The Security Stack

### 1. Hardened Container Image

```dockerfile
# Multi-stage build with distroless base
FROM golang:1.22-alpine AS builder
# ... build steps ...

FROM gcr.io/distroless/static-debian12:nonroot
# No shell, no package manager, minimal attack surface
```

**Why distroless?**
- No shell = no shell injection
- No package manager = no apt/apk exploits
- Minimal packages = minimal CVEs
- ~2MB base image

### 2. Vulnerability Scanning (Trivy)

```bash
# Scan for vulnerabilities
trivy image ghcr.io/j-dahl7/container-sbom-signing-attestation:latest

# CI/CD blocks on CRITICAL vulnerabilities
trivy image --exit-code 1 --severity CRITICAL <image>
```

### 3. SBOM Generation (Syft)

```bash
# Generate SBOM in multiple formats
syft <image> -o spdx-json > sbom.spdx.json
syft <image> -o cyclonedx-json > sbom.cdx.json
```

**What's in an SBOM?**
- All packages in the image
- Version numbers
- Licenses
- Dependencies

### 4. Keyless Signing (Cosign + Sigstore)

```bash
# Sign (in CI - uses OIDC automatically)
cosign sign --yes ghcr.io/org/image@sha256:...

# Verify (anywhere)
cosign verify ghcr.io/org/image@sha256:... \
  --certificate-identity-regexp='https://github.com/org/repo/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com'
```

**How keyless works:**
1. GitHub Actions requests OIDC token
2. Sigstore's Fulcio issues short-lived certificate
3. Certificate binds GitHub identity to signing key
4. Signature + cert stored in Rekor transparency log
5. Anyone can verify without knowing the key!

### 5. Build Provenance (SLSA)

```yaml
# GitHub native attestations
- uses: actions/attest-build-provenance@v1
  with:
    subject-name: ghcr.io/org/image
    subject-digest: ${{ steps.build.outputs.digest }}
```

**What provenance proves:**
- Where the image was built (GitHub Actions)
- What commit it came from
- Who triggered the build
- What workflow was used

---

## Verification Commands

### Verify Signature

```bash
cosign verify ghcr.io/j-dahl7/container-sbom-signing-attestation@sha256:... \
  --certificate-identity-regexp='https://github.com/j-dahl7/container-sbom-signing-attestation/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com'
```

### Verify SBOM Attestation

```bash
cosign verify-attestation ghcr.io/j-dahl7/container-sbom-signing-attestation@sha256:... \
  --type spdxjson \
  --certificate-identity-regexp='https://github.com/j-dahl7/container-sbom-signing-attestation/.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com'
```

### Extract SBOM from Attestation

```bash
cosign verify-attestation <image@digest> --type spdxjson ... \
  | jq -r '.payload' | base64 -d | jq '.predicate'
```

### View in Rekor Transparency Log

```bash
# Search Rekor for signatures
rekor-cli search --email your-github-username@users.noreply.github.com
```

---

## Zero-Trust Principles Applied

| Principle | How This Lab Implements It |
|-----------|---------------------------|
| **Never trust, always verify** | Every consumer can verify signatures |
| **Assume breach** | Keyless = no secrets to steal |
| **Least privilege** | Distroless = minimal attack surface |
| **Defense in depth** | Scan + Sign + Attest + Provenance |
| **Audit everything** | Rekor transparency log is immutable |

---

## Common Issues

### "No matching signatures found"

The image might not be signed, or you're using the wrong identity pattern:

```bash
# Check what identity signed the image
cosign verify <image> --certificate-identity-regexp='.*' \
  --certificate-oidc-issuer='https://token.actions.githubusercontent.com' 2>&1 | head -20
```

### "SBOM attestation not found"

SBOM attestation is separate from the signature:

```bash
# List all attestation types
cosign tree <image@digest>
```

### Local signing (for testing)

```bash
# Generate a keypair (NOT for production)
cosign generate-key-pair

# Sign with key
cosign sign --key cosign.key <image>

# Verify with public key
cosign verify --key cosign.pub <image>
```

---

## Resources

- **Blog Post:** [Secure Your Container Supply Chain](https://nineliveszerotrust.com/blog/container-sbom-signing-attestation/)
- **Sigstore:** https://sigstore.dev
- **Cosign:** https://github.com/sigstore/cosign
- **Syft:** https://github.com/anchore/syft
- **Trivy:** https://github.com/aquasecurity/trivy
- **SLSA:** https://slsa.dev
- **SPDX:** https://spdx.dev
- **CycloneDX:** https://cyclonedx.org

---

## License

MIT - Use freely for demos and education.
