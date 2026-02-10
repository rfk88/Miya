#!/bin/bash
# Deploy scoring guardrails: Rook webhook (sleep guardrails + active calories keys/logging)
# and optional recompute-only functions.

set -e

echo "📦 Deploying scoring guardrails (sleep + active calories)..."
echo ""

echo "1️⃣  Deploying rook (webhook + recompute)..."
supabase functions deploy rook --no-verify-jwt
echo "   ✅ rook deployed"
echo ""

echo "2️⃣  Deploying rook_daily_recompute (optional – uncomment if you use it)..."
# supabase functions deploy rook_daily_recompute --no-verify-jwt
echo "   ⏭️  Skipped (uncomment in script to deploy)"
echo ""

echo "3️⃣  Deploying recompute_vitality_scores (optional – uncomment if you use it)..."
# supabase functions deploy recompute_vitality_scores --no-verify-jwt
echo "   ⏭️  Skipped (uncomment in script to deploy)"
echo ""

echo "✅ Deployment complete!"
echo ""
echo "📋 What was deployed:"
echo "   - Sleep: derive total from stages when sleep_minutes missing; restorative/awake use effective total"
echo "   - Movement: extra active-calorie payload keys + MIYA_ACTIVE_CALORIES_MISSING log when missing"
echo ""
echo "📝 View Rook logs:"
echo "   supabase functions logs rook --follow"
echo ""
echo "   Look for 🟡 MIYA_ACTIVE_CALORIES_MISSING when steps/movement exist but active calories don’t."
echo "   See docs/DEPLOY_SCORING_GUARDRAILS.md for full steps and troubleshooting."
