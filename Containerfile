# hecate-tom-world
#
# TOM, Traders of Macao: one port and its market.
#
# ONE IMAGE, TWO PORTS. Nothing below says Macao. Which harbour an instance IS
# comes from TOM_HARBOUR in its environment, read at boot, so the same artifact
# runs Macao on one box and Lisbon on another and neither was rebuilt. The
# standings for both travel with the release in priv/harbours.

FROM docker.io/erlang:28-alpine AS builder
WORKDIR /build

# macula ships a QUIC NIF. MACULA_FORCE_SOURCE_BUILD makes it build HERE rather
# than fetch a prebuilt binary linked against a different libc, which is the
# recorded glibc trap: the fetched artifact loads on the build host and fails on
# alpine at runtime with nothing useful in the log.
RUN apk add --no-cache git curl bash build-base cmake perl linux-headers
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"
ENV RUSTFLAGS="-C target-feature=-crt-static"
ENV MACULA_FORCE_SOURCE_BUILD=1

RUN curl -fsSL https://s3.amazonaws.com/rebar3/rebar3 -o /usr/local/bin/rebar3 \
    && chmod +x /usr/local/bin/rebar3

# Dependencies resolve from rebar.config alone, so this layer survives every
# change to src/ and the Rust toolchain is not re-run per commit.
COPY rebar.config ./
RUN rebar3 get-deps

COPY config ./config
COPY priv ./priv
COPY src ./src
RUN rebar3 as prod release

FROM docker.io/alpine:3.22
LABEL org.opencontainers.image.source="https://github.com/hecate-services/hecate-tom-world"
RUN apk add --no-cache ncurses-libs libstdc++ libgcc openssl ca-certificates curl
WORKDIR /app
COPY --from=builder /build/_build/prod/rel/hecate_tom_world ./

ENV HOME=/app
ENV RELX_REPLACE_OS_VARS=true
ENV ERLANG_COOKIE=hecate_tom_world
ENV HECATE_HEALTH_PORT=8477

# THIS PORT KEEPS A RECORD AND IT MUST OUTLIVE THE CONTAINER. Custody and
# receipts live here, and losing them is losing the answer to "did that order
# already happen". A recreate without this mount is a port that will charge a
# returning house twice.
ENV TOM_DATA_DIR=/data
VOLUME ["/data"]
VOLUME ["/etc/hecate/secrets"]

EXPOSE 8477
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${HECATE_HEALTH_PORT}/health" || exit 1

CMD ["/app/bin/hecate_tom_world", "foreground"]
