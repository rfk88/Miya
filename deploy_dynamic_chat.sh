#!/bin/bash

echo "🚀 Deploying Dynamic Member Chat Fix..."
echo ""
echo "Changes:"
echo "  ✅ Fixed OpenAI API endpoint"
echo "  ✅ Fixed request/response format"
echo "  ✅ Added intent-specific prompts"
echo "  ✅ Added contextual pill generation"
echo ""

# Deploy the edge function
supabase functions deploy arlo-member-chat --no-verify-jwt

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Deployment successful!"
    echo ""
    echo "Test it now:"
    echo "  1. Open Rami's profile"
    echo "  2. Tap 'What is Rami doing well?'"
    echo "  3. Should see contextual pills appear"
else
    echo ""
    echo "❌ Deployment failed!"
    echo ""
    echo "Try:"
    echo "  1. Run: supabase login"
    echo "  2. Then run this script again"
fi
