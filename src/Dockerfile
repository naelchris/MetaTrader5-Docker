# Stage 1 — build
FROM drogonframework/drogon:latest AS builder

WORKDIR /app
COPY . .

RUN cmake -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build -j"$(nproc)"

# Stage 2 — runtime
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        libssl3 \
        libjsoncpp25 \
        libc-ares2 \
        libuuid1 \
        zlib1g \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/build/mt5_bridge /usr/local/bin/mt5_bridge

EXPOSE 8080 9000

CMD ["mt5_bridge"]
