#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMAND="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
CACHE_KEY="$(printf '%s' "$PROJECT_ROOT" | shasum -a 256 | cut -c1-12)"
CACHE_BASE="$(getconf DARWIN_USER_CACHE_DIR)ClearDisplay"
PROJECT_CACHE="$CACHE_BASE/$CACHE_KEY"
BUILD_CACHE="$PROJECT_CACHE/Build"
SOURCE_CACHE="$PROJECT_CACHE/Source"
mkdir -p "$BUILD_CACHE" "$SOURCE_CACHE"
chmod 700 "$CACHE_BASE" "$PROJECT_CACHE"
# Copy only project sources, without File Provider metadata. Atomically update
# changed contents so cloud-sync timestamp changes cannot invalidate a build.
python3 "$PROJECT_ROOT/scripts/stage-sources.py" "$PROJECT_ROOT" "$SOURCE_CACHE"
# XCTest native discovery reports all test targets in a single run.
if [[ "$COMMAND" == "test" ]]; then
    exec swift "$COMMAND" --build-system native --package-path "$SOURCE_CACHE" --scratch-path "$BUILD_CACHE" "$@"
fi
exec swift "$COMMAND" --package-path "$SOURCE_CACHE" --scratch-path "$BUILD_CACHE" "$@"
