# Base images are locked to immutable manifest digests. Dependabot proposes
# reviewed digest updates through .github/dependabot.yml.
FROM golang:1.26.11-alpine@sha256:ae52b5bc6ed045a9ed26ab03dc19327a802a9cc9aa8b27ed57f5c6b60579b0bb AS builder

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

FROM gcr.io/distroless/static-debian13:nonroot@sha256:aafe993665bf6200db38a02c11a9351e782a84b6a45e7f33b6695638c88e3931

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
