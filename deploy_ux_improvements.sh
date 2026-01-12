#!/bin/bash

# Deploy UX improvements for health insight display

set -e

echo "🎨 Deploying UX Improvements for Health Insights..."
echo ""

echo "📦 Step 1: Deploying database migration (feedback table)..."
supabase db push

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📋 What's new:"
echo "  ✅ Removed debug 'Why this matters' section"
echo "  ✅ Added medical disclaimer at top of insights"
echo "  ✅ Enhanced loading state with animated steps"
echo "  ✅ Made content sections expandable/collapsible"
echo "  ✅ Applied visual improvements (shadows, spacing, typography)"
echo "  ✅ Added feedback buttons (thumbs up/down)"
echo "  ✅ Elevated 'Reach Out' section with premium styling"
echo ""
echo "🔄 Next steps:"
echo "1. Rebuild your iOS app in Xcode (Cmd+B)"
echo "2. Run the app and test:"
echo "   - Open a family notification"
echo "   - Check that debug info is hidden"
echo "   - See the disclaimer at the top"
echo "   - Watch the loading animation"
echo "   - Expand/collapse sections"
echo "   - Test feedback buttons"
echo "   - Verify 'Reach Out' section looks premium"
echo ""
echo "📝 See UX_IMPROVEMENTS_SUMMARY.md for full details"
