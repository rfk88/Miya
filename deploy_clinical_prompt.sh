#!/bin/bash
# Deploy Clinical Prompt Update
# This script deploys the database migration and Edge Function

set -e  # Exit on error

echo "🏥 Deploying Clinical Prompt Update..."
echo ""

# Step 1: Database Migration
echo "📊 Step 1: Running database migration..."
cd "$(dirname "$0")"
supabase db push
echo "✅ Database migration complete"
echo ""

# Step 2: Deploy Edge Function
echo "🚀 Step 2: Deploying miya_insight Edge Function..."
cd supabase
supabase functions deploy miya_insight
echo "✅ Edge Function deployed"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✨ Deployment Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📱 Next steps:"
echo "  1. Rebuild the iOS app in Xcode"
echo "  2. Test by tapping a family notification"
echo "  3. Look for the new 4-section clinical format"
echo ""
echo "📖 See CLINICAL_PROMPT_UPDATE_SUMMARY.md for details"
