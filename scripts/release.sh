#!/usr/bin/env bash
set -euo pipefail

# Run from the repository root regardless of where this script is invoked from.
cd "$(dirname "$0")/.."

rm -rf build build-release dist
bash scripts/package.sh
ditto -x -k dist/Delta-Diff.zip /Applications/
