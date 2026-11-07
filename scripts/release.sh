#!/usr/bin/env bash
# Build and push a multi-architecture release to Docker Hub, then tag it in git.
# Usage: scripts/release.sh [--bump patch|minor|major|X.Y.Z]   (default: patch; run `docker login` first)
# Keep in sync with scripts/release.ps1.
set -euo pipefail

IMAGE=sriramiyer/pg-restic
PLATFORMS=linux/amd64,linux/arm64
BUILDER=pg-restic-multiarch
VERSION_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
USAGE="Usage: $0 [--bump patch|minor|major|X.Y.Z]"

fail() {
    echo "$1" >&2
    exit 1
}

# True when version $1 is higher than version $2
is_newer() {
    local IFS=.
    local -a a=($1) b=($2)
    local i
    for i in 0 1 2; do
        (( a[i] > b[i] )) && return 0
        (( a[i] < b[i] )) && return 1
    done
    return 1
}

bump=patch
case $# in
    0) ;;
    2) [ "$1" = --bump ] || fail "$USAGE"; bump=$2 ;;
    *) fail "$USAGE" ;;
esac
case $bump in
    patch | minor | major) ;;
    *) [[ "$bump" =~ $VERSION_RE ]] || fail "$USAGE" ;;
esac

cd "$(dirname "$0")/.."

[ -z "$(git status --porcelain)" ] || fail 'The working tree has uncommitted changes.'
[ "$(git branch --show-current)" = main ] || fail 'Releases are made from main.'
git fetch --quiet --tags origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail 'main does not match origin/main. Push or pull first.'

latest=$(git tag --list 'v*' --sort=-v:refname | sed 's/^v//' | grep -Em1 "$VERSION_RE" || true)
if [ -z "$latest" ] && [[ ! "$bump" =~ $VERSION_RE ]]; then
    fail 'No vX.Y.Z git tag found. Tag the current release first, or pass --bump X.Y.Z.'
fi

IFS=. read -r major minor patch <<< "${latest:-0.0.0}"
case $bump in
    patch) version="$major.$minor.$((patch + 1))" ;;
    minor) version="$major.$((minor + 1)).0" ;;
    major) version="$((major + 1)).0.0" ;;
    *) version=$bump ;;
esac
tag="v$version"

if [ -n "$latest" ] && ! is_newer "$version" "$latest"; then
    fail "Version $version is not higher than the latest release $latest."
fi
[ -z "$(git tag --list "$tag")" ] || fail "Git tag $tag already exists."
[ -z "$(git ls-remote --tags origin "refs/tags/$tag")" ] || fail "Git tag $tag already exists on origin."

answer=
read -r -p "Release $version (latest is ${latest:-none})? [y/N] " answer || true
[[ "$answer" =~ ^[yY]$ ]] || fail 'Cancelled.'

# The default docker driver can't build several platforms at once
if ! docker buildx inspect "$BUILDER" > /dev/null 2>&1; then
    docker buildx create --name "$BUILDER" --driver docker-container > /dev/null
fi

docker buildx build --builder "$BUILDER" --platform "$PLATFORMS" \
    -t "$IMAGE:$version" -t "$IMAGE:latest" --push .

git tag -a "$tag" -m "Release $version"
git push origin "$tag"

echo "Released $IMAGE:$version ($PLATFORMS) and tagged $tag."
