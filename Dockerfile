# Base images are locked to immutable manifest digests. Dependabot proposes
# reviewed digest updates through .github/dependabot.yml.
FROM golang:1.27.1-alpine@sha256:cf6fca6641884b8433441b2b0652976f975e1d0fdd26d177eaaf8596087f3125 AS builder

WORKDIR /build

COPY app/go.mod ./
RUN go mod download

COPY app/*.go ./

ARG VERSION=dev
ARG BUILD_TIME=unknown
ARG GIT_COMMIT=unknown

RUN go test ./... && \
    CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
      -trimpath \
      -ldflags="-w -s \
        -X main.Version=${VERSION} \
        -X main.BuildTime=${BUILD_TIME} \
        -X main.GitCommit=${GIT_COMMIT}" \
      -o /app .

FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3

LABEL org.opencontainers.image.title="Supply Chain Demo"
LABEL org.opencontainers.image.description="Demo app for supply chain security with signing and attestation"
LABEL org.opencontainers.image.vendor="Nine Lives Zero Trust"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.source="https://github.com/j-dahl7/container-sbom-signing-attestation"

COPY --from=builder /app /app

EXPOSE 8080
USER nonroot:nonroot

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["/app", "-health-check"]

ENTRYPOINT ["/app"]
