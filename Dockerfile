# =============================================================================
# Supply Chain Security Demo - Hardened Multi-Stage Dockerfile
# =============================================================================
# This Dockerfile demonstrates security best practices:
# - Multi-stage build (minimal final image)
# - Distroless base (no shell, no package manager)
# - Non-root user
# - Build-time metadata (for SBOM/provenance)
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build
# -----------------------------------------------------------------------------
FROM golang:1.26.5-alpine@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS builder

# Security: compile as an unprivileged user with writable caches isolated in /tmp.
RUN adduser -D -u 10001 appuser \
    && mkdir -p /build \
    && chown appuser:appuser /build

WORKDIR /build
ENV GOMODCACHE=/tmp/go-mod-cache \
    GOCACHE=/tmp/go-build-cache
USER appuser

# Copy dependency files first (better layer caching)
COPY app/go.mod ./
RUN go mod download

# Copy source code
COPY app/*.go ./

# Build with security flags and version info
ARG VERSION=dev
ARG BUILD_TIME=unknown
ARG GIT_COMMIT=unknown

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-w -s \
        -X main.Version=${VERSION} \
        -X main.BuildTime=${BUILD_TIME} \
        -X main.GitCommit=${GIT_COMMIT}" \
    -o /build/app main.go

# -----------------------------------------------------------------------------
# Stage 2: Runtime (Distroless)
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot@sha256:b7bb25d9f7c31d2bdd1982feb4dafcaf137703c7075dbe2febb41c24212b946f

# OCI Image Labels (used by SBOM tools and registries)
LABEL org.opencontainers.image.title="Supply Chain Demo"
LABEL org.opencontainers.image.description="Demo app for supply chain security with signing and attestation"
LABEL org.opencontainers.image.vendor="Nine Lives Zero Trust"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/j-dahl7/container-sbom-signing-attestation"

# Copy binary from builder
COPY --from=builder /build/app /app

# Expose port
EXPOSE 8080

# Run as non-root (distroless:nonroot already sets this, but explicit is good)
USER nonroot:nonroot

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app", "-health-check"]

ENTRYPOINT ["/app"]
