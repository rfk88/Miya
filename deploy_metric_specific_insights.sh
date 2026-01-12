#!/bin/bash
# Deploy Metric-Specific AI Insights Update
# This script deploys the Edge Function with metric-specific and severity-aware prompts

set -e  # Exit on error

echo "🎯 Deploying Metric-Specific AI Insights..."
echo ""

# Deploy Edge Function
echo "🚀 Deploying miya_insight Edge Function..."
cd "$(dirname "$0")/supabase"
supabase functions deploy miya_insight
echo "✅ Edge Function deployed"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Deployment Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📱 Next steps:"
echo "  1. Rebuild the iOS app in Xcode (no code changes needed)"
echo "  2. Test by tapping a family notification"
echo "  3. Verify metric-specific language appears"
echo ""
echo "🧪 Test these scenarios:"
echo "  - Steps alert → verify movement-specific causes/actions"
echo "  - Sleep alert → verify sleep-specific causes/actions"
echo "  - HRV alert → verify stress/recovery language"
echo "  - Different severity levels (3, 7, 14+)"
echo ""
echo "📖 See METRIC_SPECIFIC_AI_INSIGHTS_UPDATE.md for details"
