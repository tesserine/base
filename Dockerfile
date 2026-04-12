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

RUN apk add --no-cache curl gcc git glibc-dev

# Install Rust via rustup (Wolfi does not package cargo, and we need >= 1.85
# for edition 2024)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
        sh -s -- -y --default-toolchain stable --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

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
# The installer symlinks ~/.local/bin/claude -> ~/.local/share/claude/versions/<ver>.
# Copy the resolved binary (not the symlink) to a system-wide path so the
# unprivileged agent user can access it after gosu privilege drop.
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && cp -L /root/.local/bin/claude /usr/local/bin/claude \
    && rm -rf /root/.local/share/claude /root/.local/bin/claude /root/.cache/claude

# runa binary from builder stage
COPY --from=runa-builder /build/runa-bin /usr/local/bin/runa

# The runner enters via /bin/sh -lc with a generated script that creates
# the unprivileged user, clones the repo, and exec gosu's into the session
# command. No ENTRYPOINT or CMD — agentd owns the entrypoint.
