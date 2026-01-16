# ---- build stage ----
FROM golang:1.25-alpine AS builder
WORKDIR /build
COPY go.mod .
COPY go.sum .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux \
    go build -o out/demo-go ./...


# ---- runtime stage ----
FROM alpine:3
COPY --from=builder /build/out/demo-go /demo-go
EXPOSE 8080
ENTRYPOINT ["/demo-go"]