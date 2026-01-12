#!/bin/bash
# Deploy miya_insight and miya_insight_chat with chat loop fixes

set -e

echo "🚀 Deploying chat loop fixes to Supabase..."

# Deploy miya_insight (generates and caches insights)
echo "📦 Deploying miya_insight function..."
supabase functions deploy miya_insight --no-verify-jwt

# Deploy miya_insight_chat (handles chat conversations)
echo "💬 Deploying miya_insight_chat function..."
supabase functions deploy miya_insight_chat --no-verify-jwt

echo ""
echo "✅ Deployment complete!"
echo ""
echo "Next steps:"
echo "1. Run diagnose_chat_loop.sql in Supabase SQL Editor to clear stuck cache"
echo "2. Test chat on a notification"
echo "3. Check logs: supabase functions logs miya_insight"
echo "4. Check logs: supabase functions logs miya_insight_chat"
