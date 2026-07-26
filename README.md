# Container SBOM, Signing, and Attestation Lab

This is the companion lab for [Secure Your Container Supply Chain: SBOM,
Signing & Attestation with GitHub Actions](https://nineliveszerotrust.com/blog/container-sbom-signing-attestation/).
It builds a small non-root, distroless Go image and demonstrates a consumer
policy that requires three independently checkable artifacts:

1. a keyless Cosign image signature;
2. a signed SPDX SBOM attestation; and
3. signed SLSA build provenance.

All GitHub Actions and Docker base images are pinned to immutable digests or
commit SHAs. Dependabot opens reviewed update proposals instead of silently
following mutable tags.

## Trust and publication boundaries

- The workflow defaults to `contents: read`.
- Pull requests can test, build, and scan, but receive no package, OIDC, or
  attestation write permission.
- Publication is allowed only from `refs/heads/main` or a `v*` tag. A manual
  dispatch from any other ref is intentionally validation-only.
- The publication job alone receives `packages: write`, `id-token: write`, and
  `attestations: write`.
- Verification is bound to this repository's exact
  `.github/workflows/supply-chain.yml` identity and to `main` or `v*` tags.
  A signature from some other GitHub workflow is not accepted.
- Missing signature, SBOM, or provenance is a failure, not a warning.

## Repository layout

```text
app/                         Demo Go service and tests
Dockerfile                   Digest-pinned multi-stage build
scripts/check-pinned-refs.sh Immutable-reference policy
scripts/local-build.sh       Optional local build helper
scripts/verify-image.sh      Fail-closed consumer verification
tests/                       Offline security contract tests
.github/workflows/           Read-only validation and ref-gated publication
```

## Validate locally

Python 3, Bash, Go 1.22+, and Docker are required. Trivy and Syft are required
for the full local supply-chain exercise.

```bash
bash scripts/check-pinned-refs.sh
python3 -m unittest discover -s tests -v
(cd app && go test ./...)
bash scripts/local-build.sh
```

The Docker build also runs the Go tests, so a failing application test cannot
produce a release image.

## Verify a published image

Install Cosign, then pass both the immutable image reference and the expected
GitHub repository:

```bash
bash scripts/verify-image.sh \
  ghcr.io/OWNER/REPOSITORY@sha256:FULL_64_CHARACTER_DIGEST \
  OWNER/REPOSITORY
```

The repository argument is security policy, not display metadata. Use the
repository that owns this workflow; do not replace it with a wildcard. The
script exits nonzero unless the signature, SPDX SBOM, and one accepted SLSA
provenance predicate all match the same exact workflow identity.

## Pipeline

```text
pull request / main / v* tag
            |
            v
  immutable-ref guard + tests
            |
            v
  local build + config/image scans
            |
            +---- PR or untrusted manual ref: stop
            |
            v
  main or v* only: publish by digest
            |
            v
  sign + attach SPDX SBOM + attach provenance
            |
            v
  verify all three against exact GitHub identity
```

The example is intentionally opinionated: a successful build alone is not
evidence that an image is trusted. Consumers should deploy by digest only after
the verification policy passes.

## Rotation and updates

Review Dependabot proposals for Action SHAs, Docker digests, and Go modules.
The `check-pinned-refs.sh` guard blocks mutable replacements such as
`actions/checkout@v4` or `FROM image:tag`. Digest pinning preserves reviewable
inputs; it does not remove the need to apply security updates promptly.

## License

MIT. Use the lab for demos and education.
