#!/usr/bin/env bash
# Start the isolated Firebase demo and preserve Auth identities across restarts.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir/firebase"
cli="${FIREBASE_CLI:-firebase}"
args=(emulators:start --only auth,database,functions --project demo-allo-auth --export-on-exit=.emulator-data)
if [[ -f .emulator-data/firebase-export-metadata.json ]]; then
  args+=(--import=.emulator-data)
fi
exec "$cli" "${args[@]}"
