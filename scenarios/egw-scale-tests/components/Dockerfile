FROM golang:1.21 as builder

WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY main.go ./
COPY cmd ./cmd
COPY pkg ./pkg

RUN CGO_ENABLED=0 GOOS=linux go build -o /egw-scale-test

FROM scratch

COPY --from=builder /egw-scale-test /
ENTRYPOINT ["/egw-scale-test"]
