#!/usr/bin/env bash
set -euo pipefail

# Cuts a release the way `AGENTS.md` "Releasing" describes: a release is a
# tag, pushing it is what triggers `.github/workflows/release.yml` to build,
# sign and publish. This covers that step, step 1. Steps 2 (bump the
# Homebrew tap) and 3 (install and verify) stay manual, see `AGENTS.md`.

usage() {
  cat <<'EOF'
Usage: bin/release.sh [patch|minor|major]

Bumps the latest `vX.Y.Z` tag (patch by default), tags `main` with it,
pushes the tag, and watches its release run.
EOF
}

bump="${1:-patch}"
case "$bump" in
  -h | --help)
    usage
    exit 0
    ;;
  patch | minor | major) ;;
  *)
    echo "error: unknown bump '$bump', expected patch, minor or major" >&2
    usage >&2
    exit 1
    ;;
esac

repository_root="$(git rev-parse --show-toplevel)"
cd "$repository_root"

branch="$(git branch --show-current)"
if [ "$branch" != "main" ]; then
  echo "error: on branch '$branch', releases are cut from main" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree is not clean, commit or stash first" >&2
  exit 1
fi

git fetch origin main
local_head="$(git rev-parse HEAD)"
remote_head="$(git rev-parse origin/main)"
if [ "$local_head" != "$remote_head" ]; then
  echo "error: local main is not origin/main, pull or push first" >&2
  exit 1
fi

latest_tag="$(git tag --list 'v*' --sort=-v:refname | head -1)"
if [ -z "$latest_tag" ]; then
  echo "error: no existing v* tag to bump from" >&2
  exit 1
fi

version="${latest_tag#v}"
IFS='.' read -r major minor patch <<<"$version"

case "$bump" in
  patch) patch=$((patch + 1)) ;;
  minor)
    minor=$((minor + 1))
    patch=0
    ;;
  major)
    major=$((major + 1))
    minor=0
    patch=0
    ;;
esac

new_tag="v${major}.${minor}.${patch}"

echo "Latest tag: $latest_tag"
echo "New tag:    $new_tag ($bump)"
echo "At:         $local_head"
read -r -p "Tag and push $new_tag? [y/N] " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
  echo "Aborted, nothing tagged."
  exit 1
fi

git tag "$new_tag"
git push origin "$new_tag"

echo "Pushed $new_tag, waiting for its run to appear..."
# The run takes a moment to register after the push. Filtering by branch,
# rather than `--limit 1` on its own, is what keeps this from catching the
# previous tag's already-finished run, see `AGENTS.md`.
run_id=""
for _ in $(seq 1 30); do
  run_id="$(gh run list --branch "$new_tag" --workflow release.yml --limit 1 \
    --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  [ -n "$run_id" ] && break
  sleep 2
done

if [ -z "$run_id" ]; then
  repository="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  echo "error: no run found for $new_tag after 60s," \
    "check https://github.com/$repository/actions" >&2
  exit 1
fi

gh run watch "$run_id" --exit-status

echo
echo "Released $new_tag."
echo "The 'Notarize' and 'Update the Homebrew tap' steps show as skipped" \
  "without a paid Apple account and a TAP_TOKEN, that is expected."
echo "Next: bump the cask by hand, AGENTS.md \"Releasing\" step 2."
