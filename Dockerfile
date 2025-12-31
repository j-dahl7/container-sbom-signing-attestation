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
FROM golang:1.22-alpine AS builder

# Security: Don't run as root during build
RUN adduser -D -u 10001 appuser

WORKDIR /build

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
    -o /app main.go

# -----------------------------------------------------------------------------
# Stage 2: Runtime (Distroless)
# -----------------------------------------------------------------------------
FROM gcr.io/distroless/static-debian12:nonroot

# OCI Image Labels (used by SBOM tools and registries)
LABEL org.opencontainers.image.title="Supply Chain Demo"
LABEL org.opencontainers.image.description="Demo app for supply chain security with signing and attestation"
LABEL org.opencontainers.image.vendor="Nine Lives Zero Trust"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/j-dahl7/container-sbom-signing-attestation"

# Copy binary from builder
COPY --from=builder /app /app

# Expose port
EXPOSE 8080

# Run as non-root (distroless:nonroot already sets this, but explicit is good)
USER nonroot:nonroot

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app", "-health-check"] || exit 1

ENTRYPOINT ["/app"]
