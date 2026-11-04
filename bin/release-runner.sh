#!/usr/bin/env bash
set -euo pipefail

# Runs one GitHub Actions job on this Mac, the release, then unregisters.
#
# GitHub's hosted macOS runners left release jobs unassigned until they were
# cancelled, annotated "Due to capacity constraints" (measured 2026-11-04 on
# arm64 and Intel alike). A runner here does not depend on that pool.
#
# Ephemeral on purpose. The repository is public, and any workflow in it can
# target a repository runner, including a fork's pull request. Registered only
# for the length of one job, with fork workflows held for the owner's approval,
# there is nothing on this machine for a stranger's workflow to reach. Never
# install this as a service.

runner_version="2.338.2"
# From the `actions/runner` release notes for this version, `osx-arm64`.
runner_sha256="25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388"
label="stege-release"

if [ "$(uname -m)" != "arm64" ]; then
  echo "error: the release is arm64 and built natively, run this on Apple silicon" >&2
  exit 1
fi

# `codesign` refuses a self-signed identity this Mac does not trust, even read
# straight from a keychain by its hash (measured 2026-11-04). The job must not
# change trust settings itself, so the trust is granted here, once, by the
# person running the release, for code signing only. The certificate is the
# public half, extracted from a signed release. The private key never leaves
# the job's temporary keychain.
certificate="$(cd "$(dirname "$0")" && pwd)/stege-signing.cer"
if ! security verify-cert -q -c "$certificate" -p codeSign >/dev/null 2>&1; then
  echo "This Mac does not trust the Stege signing certificate for code signing yet."
  echo "Releases are signed with it, so it needs trusting once. macOS asks for your password."
  read -r -p "Trust it for code signing now? [y/N] " answer </dev/tty
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "error: not trusted, the release would fail at signing" >&2
    exit 1
  fi
  security add-trusted-cert -r trustRoot -p codeSign "$certificate"
  security verify-cert -q -c "$certificate" -p codeSign >/dev/null
fi

repository="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
archive_name="actions-runner-osx-arm64-${runner_version}.tar.gz"
cache="$HOME/Library/Caches/stege-release-runner"
archive="$cache/$archive_name"

mkdir -p "$cache"
if [ ! -f "$archive" ]; then
  curl --fail --location --silent --show-error --output "$archive.partial" \
    "https://github.com/actions/runner/releases/download/v${runner_version}/${archive_name}"
  mv "$archive.partial" "$archive"
fi

actual="$(shasum -a 256 "$archive" | cut -d' ' -f1)"
if [ "$actual" != "$runner_sha256" ]; then
  rm -f "$archive"
  echo "error: runner archive checksum mismatch, expected $runner_sha256, got $actual" >&2
  exit 1
fi

# A fresh directory per run, so nothing a job leaves behind, a checkout with
# its token or a build, outlives it.
directory="$(mktemp -d "${TMPDIR:-/tmp}/stege-release-runner.XXXXXX")"
registered=false

cleanup() {
  if [ "$registered" = true ] && [ -f "$directory/.runner" ]; then
    # Still registered means the job never ran, an ephemeral runner removes
    # itself after one. Unregistering keeps a stale runner off the repository.
    removal_token="$(gh api -X POST "repos/$repository/actions/runners/remove-token" --jq .token)"
    (cd "$directory" && ./config.sh remove --token "$removal_token") || true
  fi
  rm -rf "$directory"
}
trap cleanup EXIT

tar -xzf "$archive" -C "$directory"

registration_token="$(gh api -X POST "repos/$repository/actions/runners/registration-token" --jq .token)"
(
  cd "$directory"
  ./config.sh \
    --unattended \
    --ephemeral \
    --disableupdate \
    --url "https://github.com/$repository" \
    --token "$registration_token" \
    --name "$label-$(hostname -s)-$$" \
    --labels "$label" \
    --no-default-labels \
    --work _work
)
registered=true

echo "Runner registered, waiting for the release job..."
(cd "$directory" && ./run.sh)
