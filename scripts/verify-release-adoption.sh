#!/usr/bin/env bash
set -euo pipefail

workspace_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$workspace_root/scripts/release-check"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

seed_release_repo() {
    local source_repo="$1"
    local remote_repo="$2"

    mkdir -p "$source_repo/scripts" "$source_repo/.github/workflows"
    cp "$workspace_root/scripts/release-check" "$source_repo/scripts/release-check"
    cp "$workspace_root/scripts/checkout-runa-ref" "$source_repo/scripts/checkout-runa-ref"
    cp "$workspace_root/scripts/release-cut" "$source_repo/scripts/release-cut"
    chmod +x "$source_repo/scripts/release-check" "$source_repo/scripts/checkout-runa-ref" "$source_repo/scripts/release-cut"
    cp "$workspace_root/Dockerfile" "$source_repo/Dockerfile"
    cp "$workspace_root/.github/workflows/release.yml" "$source_repo/.github/workflows/release.yml"
    cp "$workspace_root/.github/workflows/release-metadata.yml" "$source_repo/.github/workflows/release-metadata.yml"

    cat >"$source_repo/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added

- Release ceremony tooling.

## [0.1.0] — 2026-04-13

### Added

- Initial image.
EOF

    git -C "$source_repo" init -q
    git -C "$source_repo" config user.name "base release verification"
    git -C "$source_repo" config user.email "base-release-verification@example.invalid"
    git -C "$source_repo" checkout -q -b main
    git -C "$source_repo" -c core.excludesFile=/dev/null add .
    git -C "$source_repo" commit -q -m "test: seed release verification"

    git init --bare -q "$remote_repo"
    git -C "$source_repo" remote add origin "$remote_repo"
    git -C "$source_repo" push -q -u origin main
}

assert_release_state() {
    local source_repo="$1"
    local remote_repo="$2"
    local tag="$3"
    local version

    version="$(release_from_tag "$tag")"

    if ! grep -Fq "## [$version] — $(date +%F)" "$source_repo/CHANGELOG.md"; then
        echo "CHANGELOG.md was not rolled to [$version] with today's date" >&2
        exit 1
    fi

    if [[ "$(git -C "$source_repo" cat-file -t "$tag")" != "tag" ]]; then
        echo "$tag is not an annotated tag" >&2
        exit 1
    fi

    local release_commit tag_commit
    release_commit="$(git -C "$source_repo" rev-parse HEAD)"
    tag_commit="$(git -C "$source_repo" rev-list -n 1 "$tag")"
    if [[ "$tag_commit" != "$release_commit" ]]; then
        echo "$tag does not point at the release commit" >&2
        exit 1
    fi

    if [[ -n "$(git -C "$source_repo" status --short)" ]]; then
        echo "release-cut left a dirty working tree" >&2
        exit 1
    fi

    git --git-dir="$remote_repo" rev-parse --verify --quiet refs/heads/main >/dev/null \
        || { echo "release branch was not pushed" >&2; exit 1; }
    git --git-dir="$remote_repo" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null \
        || { echo "$tag was not pushed" >&2; exit 1; }

    (cd "$source_repo" && ./scripts/release-check release "$tag")
}

verify_release_cut() {
    local name="$1"
    local tag="$2"
    local source_repo="$scratch/$name-source"
    local remote_repo="$scratch/$name-origin.git"

    seed_release_repo "$source_repo" "$remote_repo"
    (cd "$source_repo" && ./scripts/release-cut "$tag")
    assert_release_state "$source_repo" "$remote_repo" "$tag"

    echo "verified $name release adoption for $tag"
}

verify_release_cut_recovers_from_tag_push_failure() {
    local tag="v1.2.5"
    local source_repo="$scratch/rejected-tag-source"
    local remote_repo="$scratch/rejected-tag-origin.git"

    seed_release_repo "$source_repo" "$remote_repo"

    local original_head original_remote_main
    original_head="$(git -C "$source_repo" rev-parse HEAD)"
    original_remote_main="$(git --git-dir="$remote_repo" rev-parse refs/heads/main)"

    cat >"$remote_repo/hooks/update" <<'EOF'
#!/usr/bin/env sh
case "$1" in
  refs/tags/*)
    echo "rejecting tag update" >&2
    exit 1
    ;;
esac
exit 0
EOF
    chmod +x "$remote_repo/hooks/update"

    local output
    if output="$(cd "$source_repo" && ./scripts/release-cut "$tag" 2>&1)"; then
        echo "release-cut unexpectedly succeeded when the remote rejected the tag" >&2
        exit 1
    fi
    if [[ "$output" != *"rejecting tag update"* ]]; then
        echo "release-cut did not report the remote tag rejection" >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi

    if [[ "$(git --git-dir="$remote_repo" rev-parse refs/heads/main)" != "$original_remote_main" ]]; then
        echo "release-cut advanced remote main after tag push failure" >&2
        exit 1
    fi
    if git --git-dir="$remote_repo" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
        echo "release-cut left a remote tag after tag push failure" >&2
        exit 1
    fi
    if [[ "$(git -C "$source_repo" rev-parse HEAD)" != "$original_head" ]]; then
        echo "release-cut did not restore the local release commit after tag push failure" >&2
        exit 1
    fi
    if git -C "$source_repo" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
        echo "release-cut left the local tag after tag push failure" >&2
        exit 1
    fi
    if [[ -n "$(git -C "$source_repo" status --short)" ]]; then
        echo "release-cut left a dirty working tree after tag push failure" >&2
        exit 1
    fi

    rm -f "$remote_repo/hooks/update"
    (cd "$source_repo" && ./scripts/release-cut "$tag")
    assert_release_state "$source_repo" "$remote_repo" "$tag"

    echo "verified release-cut recovery after tag push failure"
}

verify_release_cut stable v1.2.3
verify_release_cut rc v1.2.4-rc.1
verify_release_cut_recovers_from_tag_push_failure
