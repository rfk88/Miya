#!/bin/bash

# Deploy cache validation fix for AI insights

set -e

echo "🔧 Deploying cache validation fix..."
echo ""

echo "📦 Step 1: Deploy miya_insight Edge Function..."
supabase functions deploy miya_insight --no-verify-jwt

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 What this fixes:"
echo "  - Validates cached insights have the new format fields"
echo "  - Auto-deletes invalid cached entries"
echo "  - Regenerates insights with correct format"
echo ""
echo "🔄 Next steps:"
echo "1. Pull down the app to refresh (swipe down on dashboard)"
echo "2. Tap on Ahmed's notification again"
echo "3. The insight should regenerate with the NEW format"
echo ""
echo "Expected logs:"
echo "  - 🔍 MIYA_INSIGHT: Cache query result { found: true, hasClinical: false, ... }"
echo "  - ⚠️ MIYA_INSIGHT: Cache hit but missing new fields, regenerating"
echo "  - 🤖 MIYA_INSIGHT: Calling OpenAI"
echo "  - ✅ MIYA_INSIGHT: OpenAI call succeeded"
echo ""
echo "Monitor with:"
echo "  supabase functions logs miya_insight --follow"
