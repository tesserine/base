# Releasing base

Audience: the release operator cutting a base repository release or release
candidate. This document assumes access to the repository, GitHub, `gh`, and a
local container runtime compatible with Docker or Podman commands.

## Release Identity

base uses one repository tag for the source release and container image. The
tag is `vX.Y.Z` for stable releases and `vX.Y.Z-rc.N` for deployment release
candidates.

Release tags follow the ecosystem grammar codified in
[ADR-0012](https://github.com/tesserine/commons/blob/main/adr/0012-ecosystem-release-version-grammar.md):
stable numeric identifiers are either `0` or a non-zero digit followed by zero
or more digits, and release-candidate ordinals are positive integers without
leading zeroes. Release-candidate numbering starts at `rc.1`.

Artifacts built from the tag must report that identity:

- The container image exposes `org.opencontainers.image.revision=<tag>`.
- The container image exposes `org.tesserine.base.ref=<tag>`.
- The container image exposes `org.tesserine.runa.ref=<immutable runa ref>`.

The runa ref must be an immutable tag or full commit SHA. base verifies that
the ref is present and immutable-shaped; ecosystem verification owns proving
that the runa ref matches the release manifest.

## Dependencies

base builds its container image from the runa workspace, pinned by the
`RUNA_REF` argument defaulted in `Dockerfile` (two `ARG RUNA_REF=` lines:
one for the runa builder stage, one for the final image's label surface).
The release workflow's container build step fails immediately if `RUNA_REF`
points at a git ref that does not exist in the runa repository.

Before cutting base:

- Verify the current `Dockerfile` `ARG RUNA_REF=` value resolves to a
  published runa tag. Run `git ls-remote --tags
  https://github.com/tesserine/runa.git "refs/tags/$RUNA_REF"` (or check via
  the [runa releases page](https://github.com/tesserine/runa/releases)).
- If updating `RUNA_REF` as part of preparing the base cut (typically to
  point at a newer runa release), publish the new runa tag first. Cutting
  base before the referenced runa tag exists will fail the container build
  step of the release workflow, leaving an orphaned base tag and no
  published GitHub Release.
- Update both `ARG RUNA_REF=` occurrences in `Dockerfile` together. The
  builder-stage value and final-image label value must match.

## Release Tooling Ownership

`scripts/release-check`, `scripts/release-cut`, and
`scripts/checkout-runa-ref` are **base-owned**. They implement the shared
release ceremony convention — canonical in
[commons RELEASE.md](https://github.com/tesserine/commons/blob/main/RELEASE.md)
and ADR-0006/0011/0012 — against base's own release surface (container image
labels, runa-ref pinning).

agentd, runa, commons, and groundwork carry structurally similar
`release-check`/`release-cut` scripts. They share ancestry from the
ecosystem-wide ceremony adoption
([commons#21](https://github.com/tesserine/commons/issues/21), which
required each release-surface repo to acquire its **own** tooling), but they
are independently owned: no repo is the tooling upstream, and a fix in one
repo's script does not propagate to the others. A ceremony-level behavior
change lands in the commons convention first; each repo then applies it to
its own implementation and tests.

## Testing the Release Tooling

Run the tooling's own tests after changing any release script:

```sh
./scripts/test-release-check          # fixture-based checks of release-check behavior
./scripts/verify-release-adoption.sh  # end-to-end: release-cut + release-check in a scratch repo
```

`verify-release-adoption.sh` seeds a throwaway git repo with base's release
tooling, cuts a stable and an RC release there, and asserts the full
ceremony state (changelog roll, annotated tag at the release commit, clean
tree, pushed refs, passing release-check). It verifies base's own ceremony
adoption — it does not police other repos.

## Updating the Pinned Claude Code

The image pins Claude Code by version, release-key fingerprint, and
per-platform sha256 (`Dockerfile`, the `CLAUDE_CODE_VERSION` block). To bump
the version:

1. Update `ARG CLAUDE_CODE_VERSION=` in `Dockerfile`.
2. Build; the build fails unless the new release's GPG-signed manifest
   verifies against the pinned fingerprint and the binary matches the
   manifest checksum.
3. Record the bump in `CHANGELOG.md` under `[Unreleased]`.

If the build fails on the fingerprint comparison, Anthropic has rotated the
release signing key. Do not copy the new fingerprint from the failing
build. Obtain it from a trusted Anthropic channel (the published
`claude-code.asc` over HTTPS cross-checked against Anthropic's
documentation), verify it out-of-band, then update
`ENV CLAUDE_CODE_RELEASE_KEY_FINGERPRINT=` and record the rotation and its
verification source in `CHANGELOG.md`.

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

The tag push runs `.github/workflows/release.yml`. That workflow restores
annotated tag refs after checkout, verifies the restored tag target still
matches the triggering event commit, and verifies annotated-tag and main-branch
ancestry with git-only checks before running repository release code. It then
builds a local container image with `BASE_REF` set to the tag, verifies image
identity, extracts release notes from `CHANGELOG.md`, and publishes the GitHub
Release. Only `vX.Y.Z-rc.N` tags are published as GitHub prereleases.

Manual GitHub Release creation, when needed after a workflow failure, uses the
same notes source and release classification.

```sh
./scripts/release-check notes "vX.Y.Z" > /tmp/base-release-notes.md
gh release create "vX.Y.Z" \
  --title "base vX.Y.Z" \
  --notes-file /tmp/base-release-notes.md \
  --verify-tag
```

For release candidates:

```sh
./scripts/release-check notes "vX.Y.Z-rc.N" > /tmp/base-release-notes.md
gh release create "vX.Y.Z-rc.N" \
  --title "base vX.Y.Z-rc.N" \
  --notes-file /tmp/base-release-notes.md \
  --verify-tag \
  --prerelease
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
