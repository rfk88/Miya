#!/usr/bin/env bash
# Probe the deployed Miya Rook webhook Edge Function (GET health check).
# Usage:
#   SUPABASE_URL="https://YOUR_PROJECT_REF.supabase.co" ./tools/verify_miya_rook_webhook.sh
set -euo pipefail

if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "Error: set SUPABASE_URL to your Supabase project URL (Settings → API)." >&2
  echo "Example: SUPABASE_URL=\"https://abcd1234.supabase.co\" $0" >&2
  exit 1
fi

base="${SUPABASE_URL%/}"
url="${base}/functions/v1/rook"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

code="$(curl -sS -o "$tmp" -w "%{http_code}" "$url")"
echo "GET $url"
echo "HTTP $code"
cat "$tmp"
echo ""

if [[ "$code" != "200" ]]; then
  echo "Expected HTTP 200 from rook function GET handler." >&2
  exit 1
fi

if ! grep -q "rook webhook alive" "$tmp"; then
  echo "Response body did not contain expected health-check marker." >&2
  exit 1
fi

echo "OK: rook edge function reachable and health check matched."
