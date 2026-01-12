#!/bin/bash
# Helper script to set up server-side scoring
# This will:
# 1. Run the migration SQL
# 2. Set the Edge Function secret
# 3. Deploy the functions

set -e

echo "🚀 Setting up server-side scoring for Miya Health"
echo ""

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found. Install it from: https://supabase.com/docs/guides/cli"
    exit 1
fi

# Check if linked
if ! supabase projects list | grep -q "xmfgdeyrpzpqptckmcbr"; then
    echo "❌ Not linked to Supabase project. Run: supabase link"
    exit 1
fi

echo "📝 Step 1: Running migration..."
echo "   This adds: schema_version, computed_at, vitality_schema_version columns"
echo ""
echo "   ⚠️  Since some migrations already exist, you'll need to run this SQL manually:"
echo ""
echo "   Go to: https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr/sql/new"
echo ""
echo "   Copy and paste this SQL:"
echo ""
cat << 'SQL'
ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS schema_version text;

ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS computed_at timestamptz;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS vitality_schema_version text;
SQL

echo ""
echo ""
read -p "Press Enter after you've run the SQL in the dashboard..."
echo ""

echo "🔐 Step 2: Setting Edge Function secret..."
echo ""
read -sp "Enter a secure secret for MIYA_ADMIN_SECRET (or press Enter to generate one): " secret
echo ""

if [ -z "$secret" ]; then
    secret=$(openssl rand -hex 32)
    echo "   Generated secret: $secret"
fi

supabase secrets set MIYA_ADMIN_SECRET="$secret" --project-ref xmfgdeyrpzpqptckmcbr

echo ""
echo "✅ Secret set!"
echo ""
echo "📦 Step 3: Deploying Edge Functions..."
echo ""

supabase functions deploy rook --project-ref xmfgdeyrpzpqptckmcbr
supabase functions deploy recompute_vitality_scores --project-ref xmfgdeyrpzpqptckmcbr

echo ""
echo "✅ All done! Server-side scoring is now set up."
echo ""
echo "📋 Summary:"
echo "   • Migration columns added"
echo "   • MIYA_ADMIN_SECRET set"
echo "   • Edge Functions deployed"
echo ""
echo "🎉 Your ROOK webhooks will now automatically compute vitality scores!"

