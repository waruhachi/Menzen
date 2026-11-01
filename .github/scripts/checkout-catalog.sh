#!/usr/bin/env bash
# Prints the path of the current apps.json from the catalog branch, or of an
# empty file when the branch doesn't exist yet.
set -euo pipefail

out="${RUNNER_TEMP:-/tmp}/current-apps.json"
if git fetch --depth=1 origin catalog 2>/dev/null; then
	git show FETCH_HEAD:apps.json >"$out" 2>/dev/null || echo '{}' >"$out"
else
	echo '{}' >"$out"
fi
echo "$out"
