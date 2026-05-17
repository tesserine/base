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
#   runa       — cognitive runtime CLI (built from source)
#   runa-mcp   — MCP server for agent communication (built from source)
#   claude     — Claude Code CLI (pinned Anthropic release binary)

# ---------------------------------------------------------------------------
# Stage 1: Build runa from source
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base AS runa-builder

RUN apk add --no-cache \
        curl \
        gcc \
        git \
        glibc-dev \
        rust-1.89

ARG RUNA_REF=v0.1.2
COPY scripts/checkout-runa-ref /usr/local/bin/checkout-runa-ref
RUN checkout-runa-ref checkout "${RUNA_REF}" /build/runa \
    && cd /build/runa \
    && cargo build --release \
    && cp target/release/runa /build/runa-bin \
    && cp target/release/runa-mcp /build/runa-mcp-bin

# ---------------------------------------------------------------------------
# Stage 2: Download and verify Claude Code
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base AS claude-downloader

RUN attempt=1; \
    until timeout 300 apk add --no-cache \
            ca-certificates-bundle \
            curl \
            gpg \
            gpg-agent \
            jq; do \
        if [ "${attempt}" -ge 3 ]; then \
            echo "Failed to install Claude Code verification dependencies after ${attempt} attempts" >&2; \
            exit 1; \
        fi; \
        attempt=$((attempt + 1)); \
        echo "Retrying Claude Code verification dependency install: attempt ${attempt}/3" >&2; \
        sleep 5; \
    done

ARG CLAUDE_CODE_VERSION=2.1.126
ENV CLAUDE_CODE_VERSION=${CLAUDE_CODE_VERSION}
ENV CLAUDE_CODE_RELEASE_KEY_FINGERPRINT=31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE

RUN timeout 900 sh -euxc '\
        release_base="https://downloads.claude.ai/claude-code-releases/${CLAUDE_CODE_VERSION}"; \
        case "$(apk --print-arch)" in \
            x86_64) claude_platform="linux-x64" ;; \
            aarch64) claude_platform="linux-arm64" ;; \
            *) echo "Unsupported Claude Code architecture: $(apk --print-arch)" >&2; exit 1 ;; \
        esac; \
        export GNUPGHOME="$(mktemp -d)"; \
        mkdir -p /usr/local/bin; \
        echo "Downloading Claude Code signing key"; \
        curl --retry 3 --retry-all-errors --connect-timeout 15 --max-time 120 \
            -fsSLo /tmp/claude-code.asc \
            https://downloads.claude.ai/keys/claude-code.asc; \
        gpg --batch --import /tmp/claude-code.asc; \
        actual_fingerprint="$(gpg --batch --with-colons --fingerprint security@anthropic.com \
            | grep "^fpr:" \
            | head -n 1 \
            | cut -d: -f10)"; \
        test "${actual_fingerprint}" = "${CLAUDE_CODE_RELEASE_KEY_FINGERPRINT}"; \
        echo "Downloading Claude Code ${CLAUDE_CODE_VERSION} manifest"; \
        curl --retry 3 --retry-all-errors --connect-timeout 15 --max-time 120 \
            -fsSLo /tmp/manifest.json \
            "${release_base}/manifest.json"; \
        curl --retry 3 --retry-all-errors --connect-timeout 15 --max-time 120 \
            -fsSLo /tmp/manifest.json.sig \
            "${release_base}/manifest.json.sig"; \
        gpg --batch --verify /tmp/manifest.json.sig /tmp/manifest.json; \
        expected_checksum="$(jq -r ".platforms[\"${claude_platform}\"].checksum" /tmp/manifest.json)"; \
        test -n "${expected_checksum}"; \
        test "${expected_checksum}" != "null"; \
        echo "Downloading Claude Code ${CLAUDE_CODE_VERSION} for ${claude_platform}"; \
        curl --retry 3 --retry-all-errors --connect-timeout 15 --max-time 600 \
            -C - \
            -fsSLo /usr/local/bin/claude \
            "${release_base}/${claude_platform}/claude"; \
        echo "${expected_checksum}  /usr/local/bin/claude" | sha256sum -c -; \
        chmod 0755 /usr/local/bin/claude; \
        rm -rf "${GNUPGHOME}" /tmp/claude-code.asc /tmp/manifest.json /tmp/manifest.json.sig \
    '

# ---------------------------------------------------------------------------
# Stage 3: Final image
# ---------------------------------------------------------------------------
FROM cgr.dev/chainguard/wolfi-base

ARG BASE_REF=local
ARG RUNA_REF=v0.1.2
ARG CLAUDE_CODE_VERSION=2.1.126

# agentd runner contract
RUN apk add --no-cache \
        bash \
        coreutils \
        curl \
        git \
        gosu \
        shadow

# Wolfi minimal image does not include /usr/local/bin
RUN mkdir -p /usr/local/bin

# Claude Code from a pinned Anthropic release. The downloader stage verifies
# the release manifest signature and binary checksum before this copy.
COPY --from=claude-downloader /usr/local/bin/claude /usr/local/bin/claude

# runa CLI and MCP server from builder stage
COPY --from=runa-builder /build/runa-bin /usr/local/bin/runa
COPY --from=runa-builder /build/runa-mcp-bin /usr/local/bin/runa-mcp

LABEL org.opencontainers.image.title="tesserine/base" \
      org.opencontainers.image.description="Reference container image for agentd agent sessions" \
      org.opencontainers.image.source="https://github.com/tesserine/base" \
      org.opencontainers.image.revision="${BASE_REF}" \
      org.tesserine.base.ref="${BASE_REF}" \
      org.tesserine.runa.ref="${RUNA_REF}" \
      org.tesserine.claude-code.version="${CLAUDE_CODE_VERSION}"

# The runner enters via /bin/sh -lc with a generated script that creates
# the unprivileged user, clones the repo, and exec gosu's into the session
# command. No ENTRYPOINT or CMD — agentd owns the entrypoint.
