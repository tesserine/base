# Releasing base

Audience: the release operator cutting a base repository release or release
candidate. This document assumes access to the repository, GitHub, `gh`, and a
local container runtime compatible with Docker or Podman commands.

## Release Identity

base uses one repository tag for the source release and container image. The
tag is `vX.Y.Z` for stable releases and `vX.Y.Z-rc.N` for deployment release
candidates.

Release tags follow Semantic Versioning 2.0.0 numeric grammar: each integer is
either `0` or a non-zero digit followed by zero or more digits. The
ecosystem-wide codification is tracked in tesserine/commons#26.

Artifacts built from the tag must report that identity:

- The container image exposes `org.opencontainers.image.revision=<tag>`.
- The container image exposes `org.tesserine.base.ref=<tag>`.
- The container image exposes `org.tesserine.runa.ref=<immutable runa ref>`.

The runa ref must be an immutable tag or full commit SHA. base verifies that
the ref is present and immutable-shaped; ecosystem verification owns proving
that the runa ref matches the release manifest.

## Pre-Release Gate

A releasable commit is on `main`, up to date with `origin/main`, and has a
clean working tree. `--allow-dirty` is not part of the release path.

Before cutting a release:

```sh
git checkout main
git pull --ff-only
git status --short
./scripts/release-check metadata
```

For a final tag-time check against an image built from the release tag:

```sh
podman build \
  --build-arg BASE_REF="vX.Y.Z" \
  --tag "localhost/base:vX.Y.Z" \
  .
./scripts/release-check release "vX.Y.Z" \
  --container-image "localhost/base:vX.Y.Z"
```

Use `BASE_CONTAINER_RUNTIME=docker` when Docker should be used instead of
Podman.

## Atomic Release Operation

Stable releases and deployment release candidates use the same repo-owned
operation:

```sh
./scripts/release-cut "vX.Y.Z"
```

For release candidates:

```sh
./scripts/release-cut "vX.Y.Z-rc.N"
```

The command verifies the clean `main` precondition, rolls `CHANGELOG.md` from
`[Unreleased]` into `[X.Y.Z] — YYYY-MM-DD`, commits that release roll, creates
an annotated tag, and atomically pushes `main` plus the tag. If that
publication push fails, the command restores the local pre-release state and
removes the generated local tag so the release can be rerun after the cause is
fixed. Release candidates are immutable refs for deployment testing. A bad or
superseded candidate is
corrected by cutting the next `rc.N`, not by rewriting the existing tag.

## Post-Release Gate

The tag push runs `.github/workflows/release.yml`. That workflow verifies the
annotated tag, builds a local container image with `BASE_REF` set to the tag,
verifies image identity, extracts release notes from `CHANGELOG.md`, and
publishes the GitHub Release. Only `vX.Y.Z-rc.N` tags are published as GitHub
prereleases.

Manual GitHub Release creation, when needed after a workflow failure, uses the
same notes source:

```sh
./scripts/release-check notes "vX.Y.Z" > /tmp/base-release-notes.md
gh release create "vX.Y.Z" \
  --title "base vX.Y.Z" \
  --notes-file /tmp/base-release-notes.md \
  --verify-tag
```

## Failure Modes

If a published tag points at source that violates release identity checks, the
tag is invalid. If it has no external consumers, delete it locally and
remotely and re-run the release operation. If it has external consumers, leave
the bad tag in the public record and cut the next version.

If the GitHub Release workflow fails after the tag is valid, repair the
workflow or environment and create the GitHub Release from
`scripts/release-check notes`. Do not edit release notes by hand unless the
changelog section is also corrected in source.
