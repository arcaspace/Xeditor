#!/usr/bin/env bash
# Fetch pinned third-party sources and generate the Xcode project.
set -euo pipefail
cd "$(dirname "$0")/.."

git submodule update --init --recursive

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not found — install it with: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
echo "Ready: open Xeditor.xcodeproj or run 'make build'."
