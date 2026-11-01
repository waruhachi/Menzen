#!/usr/bin/env bash
# Merges a staging folder (catalog.py charts/request --out) onto the catalog
# branch and pushes it. When another run pushed first, the merge is redone on
# top of theirs rather than rebased, so neither run's apps are lost.
#
#   publish-catalog.sh <stage> <commit message>
#
# Run from the repository checkout; uses ./catalog as a worktree.
set -euo pipefail

stage=$1
message=$2
scripts=$(cd "$(dirname "$0")" && pwd)
branch=catalog

git config user.name "github-actions[bot]"
git config user.email "41898283+github-actions[bot]@users.noreply.github.com"

for attempt in 1 2 3 4 5; do
	git worktree remove --force catalog 2>/dev/null || true
	if git fetch --depth=1 origin "$branch" 2>/dev/null; then
		git worktree add --detach catalog FETCH_HEAD
	else
		# First run: the branch starts empty, with no history from main.
		git worktree add --detach catalog
		git -C catalog checkout --orphan "$branch-new"
		git -C catalog rm -rfq .
	fi

	python3 -I "$scripts/catalog.py" merge --stage "$stage" --catalog catalog
	git -C catalog add -A
	if git -C catalog diff --cached --quiet; then
		echo "Nothing new to publish."
		exit 0
	fi
	git -C catalog commit -qm "$message"
	if git -C catalog push origin "HEAD:refs/heads/$branch"; then
		exit 0
	fi
	echo "Push was rejected (attempt $attempt); retrying on the latest catalog."
	sleep $((attempt * 5))
done
echo "Couldn't publish the catalog." >&2
exit 1
