#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_FILE="${PROJECT_FILE:-$ROOT_DIR/PAMFlow.xcodeproj/project.pbxproj}"
REMOTE="${REMOTE:-origin}"

log() {
    printf '[PAMFlow Release] %s\n' "$1"
}

fail() {
    printf '[PAMFlow Release] Error: %s\n' "$1" >&2
    exit 1
}

version="$(
    awk -F ' = ' '/MARKETING_VERSION = / {
        gsub(/;$/, "", $2)
        print $2
        exit
    }' "$PROJECT_FILE"
)"

if [[ -z "$version" ]]; then
    fail "Could not read MARKETING_VERSION from $PROJECT_FILE."
fi

tag="v$version"

cd "$ROOT_DIR"

if ! git diff --quiet || ! git diff --cached --quiet; then
    fail "Working tree has uncommitted changes. Commit the release changes before tagging $tag."
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    fail "Local tag $tag already exists. Bump MARKETING_VERSION before creating another release tag."
fi

if git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$tag" >/dev/null 2>&1; then
    fail "Remote tag $tag already exists on $REMOTE. Bump MARKETING_VERSION before creating another release tag."
fi

log "Creating tag $tag"
git tag "$tag"

log "Pushing tag $tag to $REMOTE"
git push "$REMOTE" "$tag"

log "Pushed $tag"
