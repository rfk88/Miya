#!/bin/bash

# Deploy comprehensive logging to diagnose AI insight failure

set -e

echo "🔧 Deploying diagnostic logs..."

echo ""
echo "📦 Deploying miya_insight Edge Function with comprehensive logging..."
supabase functions deploy miya_insight --no-verify-jwt

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 Next steps:"
echo "1. Rebuild your iOS app in Xcode (Cmd+B)"
echo "2. Run the app and trigger an AI insight"
echo "3. Check Xcode console for logs prefixed with:"
echo "   - 🤖 AI_INSIGHT: (iOS app logs)"
echo "   - ❌ AI_INSIGHT: (iOS error logs)"
echo "4. Check Supabase Edge Function logs for:"
echo "   - 🎯 MIYA_INSIGHT: (Edge Function entry)"
echo "   - 📊 MIYA_INSIGHT: (Data preparation)"
echo "   - 🤖 MIYA_INSIGHT: (AI call)"
echo "   - ✅ MIYA_INSIGHT: (Success)"
echo "   - ❌ MIYA_INSIGHT: (Errors)"
echo ""
echo "Command to watch Edge Function logs:"
echo "  supabase functions logs miya_insight --follow"
