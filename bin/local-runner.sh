#!/usr/bin/env bash
set -euo pipefail

# Runs queued GitHub Actions jobs on this Mac, one ephemeral runner per job.
#
# Every workflow in `stege` and `homebrew-stege` targets a label only this
# runner carries, so nothing runs until this does. Pull request checks use
# `stege-local`. The release uses `stege-release`, its own, so a release runner
# can never take a queued pull request job instead. GitHub's hosted macOS runners left
# jobs unassigned until they were cancelled, annotated "Due to capacity
# constraints" (measured 2026-11-04 on arm64 and Intel alike), so they are not
# used at all.
#
# Ephemeral on purpose. Both repositories are public, and any workflow in them
# can target a repository runner, including a fork's pull request. Registered
# only for the length of one job, with fork workflows held for the owner's
# approval, there is nothing on this machine for a stranger's workflow to
# reach. Never install this as a service.

usage() {
  cat <<'EOF'
Usage: bin/local-runner.sh [--repository owner/name] [--jobs N] [--label name]

Takes N queued jobs (1 by default) for the label (`stege-local` by default) in
the repository (this one by default), one fresh runner each, then exits.

  bin/local-runner.sh --jobs 2                                    # a stege pull request, Test and Build
  bin/local-runner.sh --repository xrhstosmour/homebrew-stege     # a tap pull request, Audit
  bin/release.sh                                                  # a release, starts this itself
EOF
}

repository=""
jobs=1
label="stege-local"
while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      label="${2:?--label needs a name}"
      shift 2
      ;;
    --repository)
      repository="${2:?--repository needs owner/name}"
      shift 2
      ;;
    --jobs)
      jobs="${2:?--jobs needs a number}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --jobs must be a positive number, got '$jobs'" >&2
  exit 1
fi

runner_version="2.338.2"
# From the `actions/runner` release notes for this version, `osx-arm64`.
runner_sha256="25a065af409ffa317ab4d5a3b614dd15fc9c40f2172bc1b35a1b1258e919a388"

case "$label" in
  stege-local | stege-release) ;;
  *)
    echo "error: unknown label '$label', expected stege-local or stege-release" >&2
    exit 1
    ;;
esac

if [ "$(uname -m)" != "arm64" ]; then
  echo "error: the release is arm64 and built natively, run this on Apple silicon" >&2
  exit 1
fi

# `codesign` refuses a self-signed identity this Mac does not trust, even read
# straight from a keychain by its hash (measured 2026-11-04). The job must not
# change trust settings itself, so the trust is granted here, once, by the
# person running the runner, for code signing only. The certificate is the
# public half, extracted from a signed release. The private key never leaves
# the release job's temporary keychain.
certificate="$(cd "$(dirname "$0")" && pwd)/stege-signing.cer"
if ! security verify-cert -q -c "$certificate" -p codeSign >/dev/null 2>&1; then
  echo "This Mac does not trust the Stege signing certificate for code signing yet."
  echo "Releases are signed with it, so it needs trusting once. macOS asks for your password."
  read -r -p "Trust it for code signing now? [y/N] " answer </dev/tty
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "error: not trusted, a release would fail at signing" >&2
    exit 1
  fi
  security add-trusted-cert -r trustRoot -p codeSign "$certificate"
  security verify-cert -q -c "$certificate" -p codeSign >/dev/null
fi

if [ -z "$repository" ]; then
  repository="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
fi
archive_name="actions-runner-osx-arm64-${runner_version}.tar.gz"
cache="$HOME/Library/Caches/stege-local-runner"
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

directory=""
registered=false

cleanup() {
  if [ "$registered" = true ] && [ -f "$directory/.runner" ]; then
    # Still registered means the job never ran, an ephemeral runner removes
    # itself after one. Unregistering keeps a stale runner off the repository.
    removal_token="$(gh api -X POST "repos/$repository/actions/runners/remove-token" --jq .token)"
    (cd "$directory" && ./config.sh remove --token "$removal_token") || true
  fi
  if [ -n "$directory" ]; then rm -rf "$directory"; fi
  registered=false
}
trap cleanup EXIT

for job in $(seq 1 "$jobs"); do
  # A fresh directory per job, so nothing a job leaves behind, a checkout with
  # its token or a build, outlives it or reaches the next one.
  directory="$(mktemp -d "${TMPDIR:-/tmp}/stege-local-runner.XXXXXX")"
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
      --name "$label-$(hostname -s)-$$-$job" \
      --labels "$label" \
      --no-default-labels \
      --work _work
  )
  registered=true

  echo "Runner $job of $jobs registered on $repository, waiting for a job..."
  (cd "$directory" && ./run.sh)
  cleanup
done
