#!/bin/bash

echo "🚀 Deploying Notification Chat Data Fix..."
echo ""
echo "Critical Fixes:"
echo "  ✅ HRV alerts now send actual HRV values (ms), not pillar scores"
echo "  ✅ Resting HR, sleep, steps alerts send correct raw values"
echo "  ✅ Added trending view (direction, % change, min/max/avg)"
echo "  ✅ AI receives trending summary for easier interpretation"
echo ""

# Deploy the edge function
supabase functions deploy miya_insight_chat --no-verify-jwt

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Deployment successful!"
    echo ""
    echo "Test the fix:"
    echo "  1. Open an HRV alert notification"
    echo "  2. Check chat message shows ACTUAL HRV values (like 65ms, 72ms, 80ms)"
    echo "  3. Verify trend direction matches the numbers (improving = ↑)"
    echo "  4. Check AI interpretation is correct (no more backwards advice)"
    echo ""
    echo "Before: 31/100, 45/100 labeled as 'ms' = AI says 'drop in HRV'"
    echo "After: Actual HRV values with trend = AI says correct interpretation"
else
    echo ""
    echo "❌ Deployment failed!"
    echo ""
    echo "Try:"
    echo "  1. Run: supabase login"
    echo "  2. Then run this script again"
fi
