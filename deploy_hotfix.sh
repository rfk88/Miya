#!/bin/bash
# Deploy Hotfix for AI Insights Failure
# Fixes undefined primaryMetric and adds error handling

set -e  # Exit on error

echo "🔧 Deploying AI Insights Hotfix..."
echo ""

# Deploy Edge Function
echo "🚀 Deploying miya_insight Edge Function..."
cd "$(dirname "$0")/supabase"
supabase functions deploy miya_insight
echo "✅ Edge Function deployed"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Hotfix Deployed!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🔍 What was fixed:"
echo "  - Undefined primaryMetric fallback added"
echo "  - Template functions wrapped in try-catch"
echo "  - AI call failure now returns deterministic fallback"
echo "  - Safe property access with optional chaining"
echo ""
echo "📱 Next steps:"
echo "  1. Rebuild the iOS app in Xcode"
echo "  2. Test by tapping a family notification"
echo "  3. Verify AI insights appear (not raw debugWhy text)"
echo ""
echo "📖 See HOTFIX_AI_INSIGHTS_FAILURE.md for details"
