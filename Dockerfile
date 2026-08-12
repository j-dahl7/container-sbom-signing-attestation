# Base images are locked to immutable manifest digests. Dependabot proposes
# reviewed digest updates through .github/dependabot.yml.
FROM golang:1.26.5-alpine@sha256:0178a641fbb4858c5f1b48e34bdaabe0350a330a1b1149aabd498d0699ff5fb2 AS builder

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

FROM gcr.io/distroless/static-debian12:nonroot@sha256:1b7b9f0f0e0a1d2155f531db587cc48ec26aaf97ab64364225f5bf18a054e66a

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
