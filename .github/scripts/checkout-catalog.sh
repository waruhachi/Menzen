#!/usr/bin/env bash
# Prints a folder holding the catalog branch's current files, empty when the
# branch doesn't exist yet.
set -euo pipefail

out="${RUNNER_TEMP:-/tmp}/current-catalog"
rm -rf "$out"
mkdir -p "$out"
if git fetch --depth=1 origin catalog 2>/dev/null; then
	git archive FETCH_HEAD | tar -x -C "$out"
fi
echo "$out"
