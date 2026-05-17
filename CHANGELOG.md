# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Release ceremony tooling now verifies the base changelog, Dockerfile label
  surface, tag-time image identity, and GitHub Release publication path.

### Changed

- `Dockerfile` `ARG RUNA_REF` defaults updated to `v0.1.2` (the published
  stable runa release) on both the builder-stage and final-image label lines.
  `README.md` build examples updated to reference current stable component
  tags.
- `RELEASING.md` documents the `RUNA_REF` dependency on a published runa tag,
  with operator guidance for the cut sequence when updating `RUNA_REF`.

### Fixed

- GitHub Release publication now restores annotated tag refs after checkout and
  verifies the restored tag still targets the triggering event commit before
  running repository release code, addressing the cross-repo `commons#34`
  release fix.
- Release artifact validation now rejects an explicit empty `--container-image`
  value instead of silently treating it as omitted.
- Release tag validation now rejects `rc.0` release candidates across tag,
  changelog heading, `RUNA_REF`, and GitHub Release classification surfaces to
  match the ADR-0012 release grammar.
- GitHub Release publication now establishes annotated-tag and main-ancestry
  trust before running repository release code from the tagged checkout.
- `RUNA_REF` tag checkout now resolves SemVer-shaped values only through
  explicit tag refs so homonymous branches cannot shadow release inputs.
- Release tag validation now rejects leading-zero numeric identifiers so base
  release tags match the ecosystem SemVer grammar.
- GitHub Release publication now triggers for documented release tags and lets
  `release-check` reject malformed `v*` tags before container work begins.
- Release tooling now checks out `RUNA_REF` values through the same tag-or-SHA
  path that the Dockerfile uses, so verifier acceptance matches build
  capability.
- `RUNA_REF` SHA checkout now rejects non-commit objects so container labels
  cannot name an annotated tag object while building the tagged commit.
- Manual GitHub Release recovery guidance now preserves prerelease
  classification for release candidate tags.
- `release-cut` now publishes the release commit and tag with an atomic push
  and restores local state after publication failures so reruns do not require
  manual cleanup.
- Image builds now expose OCI and Tesserine labels for the base ref, runa ref,
  and Claude Code version so deployment contents can be inspected without
  entering a container.
- README build guidance now requires deployment refs to use immutable tags or
  full SHAs instead of mutable branch names such as `main`.
- README agentd configuration example now uses the current `[[agents]]` schema
  with structured command argv.
- Claude Code installation now uses a pinned Anthropic release binary verified
  through the signed release manifest instead of the opaque latest installer.
- runa builder stage now uses Wolfi's packaged Rust toolchain instead of
  installing a floating rustup stable toolchain during image builds.

## [0.1.0] — 2026-04-13

Reference container image for agentd agent sessions. Wolfi-based, multi-stage
build that satisfies the agentd runner contract and ships runa + Claude Code.
Validated in the first live integration test (April 12, 2026).

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
