# Build stage
FROM debian:bookworm-slim AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        make \
        libc6-dev \
        git \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

# Mark workdir safe so `git describe --tags` works for version string
RUN git config --global --add safe.directory /src \
    && mkdir -p tmp bin \
    && make -j"$(nproc)"

# Runtime stage
FROM debian:bookworm-slim

# masscan loads libpcap dynamically at runtime; needs CAP_NET_RAW.
# Run with --cap-add=NET_RAW (or --network host).
RUN apt-get update && apt-get install -y --no-install-recommends \
        libpcap0.8 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/bin/masscan /usr/bin/masscan

ENTRYPOINT ["masscan"]
CMD ["--help"]
