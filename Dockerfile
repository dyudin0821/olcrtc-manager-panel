# syntax=docker/dockerfile:1

FROM node:24-bookworm-slim AS frontend

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@9 --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY index.html postcss.config.js tailwind.config.ts tsconfig.json vite.config.ts ./
COPY src/ ./src/

RUN pnpm build


FROM golang:1.26-trixie AS olcrtc-build

ARG OLCRTC_REF=5051ea7c8f4619166b71c174c848e157761e3b3e
ARG OLCRTC_REPO=https://github.com/openlibrecommunity/olcrtc.git

RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*

RUN git clone "${OLCRTC_REPO}" /src/olcrtc && \
    git -C /src/olcrtc checkout "${OLCRTC_REF}"

WORKDIR /src/olcrtc

RUN mkdir -p /out && \
    CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/olcrtc ./cmd/olcrtc


FROM golang:1.26-trixie AS manager-build

WORKDIR /src

COPY go.mod go.sum* ./
RUN go mod download

COPY cmd/ ./cmd/
COPY --from=frontend /app/cmd/olcrtc-manager/web/dist/ ./cmd/olcrtc-manager/web/dist/

RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/olcrtc-manager ./cmd/olcrtc-manager


FROM debian:trixie-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
        iproute2 \
        iptables \
        ca-certificates \
        openssl \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY --from=olcrtc-build  /out/olcrtc          /usr/local/bin/olcrtc
COPY --from=manager-build /out/olcrtc-manager  /usr/local/bin/olcrtc-manager
COPY docker/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh /usr/local/bin/olcrtc /usr/local/bin/olcrtc-manager

ENV OLCRTC_PATH=/usr/local/bin/olcrtc

EXPOSE 8443

ENTRYPOINT ["/entrypoint.sh"]
