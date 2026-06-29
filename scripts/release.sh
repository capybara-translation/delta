#!/usr/bin/env bash

rm -rf build build-release dist
bash scripts/package.sh
ditto -x -k dist/Delta-Diff.zip /Applications/
