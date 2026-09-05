# syntax=docker/dockerfile:1.7

# ---- Build stage ----
# Sprint 11.5 Slice 4 — pinned to a specific @sha256 digest (OWASP A06 +
# A08). The trailing comment names the human-readable tag at the time of
# pinning; Dependabot's docker ecosystem will surface updates as new
# tags publish.
FROM hexpm/elixir:1.19.5-erlang-28.1-alpine-3.21.7@sha256:ab47a6c9ea28d8e49cf6dd1b46ff31b7d347e7bc1d94a3bffbd457d858bd761b AS builder

# Install build deps (gcc + git for hex packages with NIFs)
RUN apk add --no-cache build-base git nodejs npm

WORKDIR /app

ENV MIX_ENV=prod \
    LANG=C.UTF-8

# Pre-build secret scan: refuse to build an image with leaked secrets in the
# source tree. The scan covers the working copy at build time (not git history,
# which is handled in CI).
COPY scripts ./scripts
COPY .secretsignore ./.secretsignore
RUN chmod +x scripts/*.sh && scripts/secret-scan.sh --pre-build || (echo "secret-scan blocked the build" && exit 1)

COPY mix.exs mix.lock ./
RUN mix do local.hex --force, local.rebar --force, deps.get --only prod

COPY config config
RUN mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib

RUN mix assets.deploy
RUN mix release

# ---- Runtime stage ----
# Pinned to the alpine:3.21 multi-arch index digest (Sprint 11.5 Slice 4).
FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS runtime

# Chromium for ChromicPDF + ncurses/openssl for BEAM
RUN apk add --no-cache openssl ncurses-libs libstdc++ chromium ca-certificates tini \
    && adduser -D -h /app app

WORKDIR /app

ENV LANG=C.UTF-8 \
    PHX_SERVER=true \
    HOME=/app

COPY --from=builder --chown=app:app /app/_build/prod/rel/guildford_vue ./

USER app

EXPOSE 4000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["bin/guildford_vue", "start"]
