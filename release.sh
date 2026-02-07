#!/bin/bash
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version> [BUILD=number]"
  exit 1
fi

CHANGELOG="CHANGELOG.md"
PLIST="Info.plist"
BUILD="${BUILD:-}"
TAG="v${VERSION}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a git repository."
  exit 1
fi

if [ ! -f "$CHANGELOG" ]; then
  echo "Error: CHANGELOG.md not found."
  exit 1
fi

if ! grep -Eq "^##[[:space:]]+${VERSION}([[:space:]]|$|—)" "$CHANGELOG"; then
  echo "Error: CHANGELOG.md is missing section for version ${VERSION}."
  echo "Add a section like: \"## ${VERSION} — YYYY-MM-DD\" before releasing."
  exit 1
fi

if [ -f "$PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" "$PLIST"

  if [ -z "$BUILD" ]; then
    CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST" 2>/dev/null || echo "")
    if [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
      BUILD=$((CURRENT_BUILD + 1))
    else
      BUILD=$(date +%s)
    fi
  fi

  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD}" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD}" "$PLIST"
  echo "Updated Info.plist to ${VERSION} (${BUILD})"
fi

git add -A

if git diff --cached --quiet; then
  echo "No changes to commit."
  exit 1
fi

git commit -m "release: ${VERSION}"
git push

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Error: tag ${TAG} already exists."
  exit 1
fi

git tag "$TAG"
git push origin "$TAG"

echo "Release tag pushed: ${TAG}"
