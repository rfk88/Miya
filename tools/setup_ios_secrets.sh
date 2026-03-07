#!/usr/bin/env bash
# Creates Miya Health/Secrets.xcconfig from the example if it doesn't exist.
# Run from repo root: ./tools/setup_ios_secrets.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE="$REPO_ROOT/Miya Health/Secrets.xcconfig.example"
TARGET="$REPO_ROOT/Miya Health/Secrets.xcconfig"

if [[ -f "$TARGET" ]]; then
  echo "Miya Health/Secrets.xcconfig already exists."
  exit 0
fi

if [[ ! -f "$EXAMPLE" ]]; then
  echo "Error: Example file not found: $EXAMPLE" >&2
  exit 1
fi

cp "$EXAMPLE" "$TARGET"
echo "Created Miya Health/Secrets.xcconfig from example. Edit it and add your ROOK and Supabase keys before running the app."
