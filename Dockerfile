# tesserine/base — reference container image for agentd agent sessions
#
# Satisfies the agentd runner contract:
#   /bin/sh    — entrypoint shell
#   useradd    — unprivileged user creation (from shadow)
#   gosu       — privilege drop after setup
#   git        — repository cloning
#   chown      — home directory ownership (from coreutils)
#
# Ships with:
#   runa       — cognitive runtime (built from source)
#   claude     — Claude Code CLI (Anthropic native installer)

# ---------------------------------------------------------------------------
# Stage 1: Build runa from source
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base AS runa-builder

RUN apk add --no-cache rust cargo git

ARG RUNA_REF=v0.1.0
RUN git clone --depth 1 --branch "${RUNA_REF}" \
        https://github.com/tesserine/runa.git /build/runa \
    && cd /build/runa \
    && cargo build --release \
    && cp target/release/runa /build/runa-bin

# ---------------------------------------------------------------------------
# Stage 2: Final image
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base

# agentd runner contract
RUN apk add --no-cache \
        bash \
        coreutils \
        curl \
        git \
        gosu \
        shadow

# Claude Code — native installer (no Node.js required on glibc)
RUN curl -fsSL https://claude.ai/install.sh | bash

# runa binary from builder stage
COPY --from=runa-builder /build/runa-bin /usr/local/bin/runa

# The runner enters via /bin/sh -lc with a generated script that creates
# the unprivileged user, clones the repo, and exec gosu's into the session
# command. No ENTRYPOINT or CMD — agentd owns the entrypoint.
