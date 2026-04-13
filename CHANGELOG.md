# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Reference container image for agentd agent sessions. Wolfi-based, multi-stage
build that satisfies the agentd runner contract and ships runa + Claude Code.

### Added

- Multi-stage Dockerfile: Rust builder stage compiles runa and runa-mcp from
  source (pinned to v0.1.0), final stage installs Claude Code via native
  installer.
- Satisfies agentd runner contract: bash, useradd, gosu, git, coreutils.
- Claude Code binary dereferenced from installer symlink and placed at
  `/usr/local/bin/claude` for unprivileged access after gosu privilege drop.
- runa CLI and runa-mcp server both available at `/usr/local/bin/`.

### Fixed

- Dereference Claude Code installer symlink with `cp -L` (symlink target
  was lost when moved to system path).
- Create `/usr/local/bin` explicitly (Wolfi minimal image does not include
  this directory).
- Include `runa-mcp` binary alongside `runa` in the final image (runa needs
  its MCP server sibling for agent communication during protocol execution).
