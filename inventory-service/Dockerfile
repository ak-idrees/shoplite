
# =========================
# STAGE 1: BUILDER
# =========================
FROM golang:1.26-alpine AS builder

WORKDIR /app

COPY go.mod go.sum ./

RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /inventory-service .


# =========================
# STAGE 2: FINAL
# =========================
FROM gcr.io/distroless/static-debian12:nonroot AS final

WORKDIR /

COPY --from=builder /inventory-service /inventory-service

ENV PORT=8081

EXPOSE 8081

USER nonroot:nonroot

ENTRYPOINT ["/inventory-service"]
HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=5 CMD ["/inventory-service", "-healthcheck"]
