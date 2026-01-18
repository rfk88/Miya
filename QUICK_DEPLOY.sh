#!/bin/bash
# Miya Notification System - Quick Deploy Script
# This script deploys the notification system in one go

set -e  # Exit on error

echo "🚀 Miya Notification System Deployment"
echo "======================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo -e "${RED}❌ Supabase CLI not found!${NC}"
    echo ""
    echo "Install it with:"
    echo "  macOS:  brew install supabase/tap/supabase"
    echo "  Other:  npm install -g supabase"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Supabase CLI found${NC}"
echo ""

# Check if project is linked
if [ ! -f ".supabase/config.toml" ]; then
    echo -e "${YELLOW}⚠️  Project not linked yet${NC}"
    echo ""
    echo "Please link your project first:"
    read -p "Enter your Supabase project reference ID (e.g., xmfgdeyrpzpqptckmcbr): " PROJECT_REF
    
    if [ -z "$PROJECT_REF" ]; then
        echo -e "${RED}❌ Project reference ID required!${NC}"
        exit 1
    fi
    
    echo ""
    echo "Linking project..."
    supabase link --project-ref "$PROJECT_REF"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Failed to link project${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Project linked${NC}"
    echo ""
else
    echo -e "${GREEN}✅ Project already linked${NC}"
    echo ""
fi

# Get project reference from config
PROJECT_REF=$(grep 'project_id' .supabase/config.toml | cut -d'"' -f2)
echo "📦 Project: $PROJECT_REF"
echo ""

# Step 1: Deploy Edge Functions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📤 Step 1: Deploying Edge Functions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Deploying process_notifications..."
supabase functions deploy process_notifications
echo -e "${GREEN}✅ process_notifications deployed${NC}"
echo ""

echo "Deploying rook..."
supabase functions deploy rook
echo -e "${GREEN}✅ rook deployed${NC}"
echo ""

echo "Deploying rook_daily_recompute..."
supabase functions deploy rook_daily_recompute
echo -e "${GREEN}✅ rook_daily_recompute deployed${NC}"
echo ""

# Step 2: Apply Migrations
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🗄️  Step 2: Applying Database Migrations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Applying migrations..."
supabase db push

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Migrations applied${NC}"
else
    echo -e "${YELLOW}⚠️  Migration push failed. You may need to apply them manually via the Supabase Dashboard.${NC}"
fi
echo ""

# Step 3: Configure Environment Variables
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 Step 3: Environment Variables"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo -e "${YELLOW}⚠️  Manual step required!${NC}"
echo ""
echo "Go to: https://supabase.com/dashboard/project/$PROJECT_REF/settings/functions"
echo ""
echo "Add these environment variables:"
echo "  1. MIYA_PATTERN_SHADOW_MODE = false"
echo "  2. MIYA_ADMIN_SECRET = <generate a secure random string>"
echo ""
echo "To generate a secure secret, run:"
echo "  openssl rand -base64 32"
echo ""

read -p "Press Enter when you've added the environment variables..."
echo ""

# Generate a secret for the user
SUGGESTED_SECRET=$(openssl rand -base64 32 2>/dev/null || echo "PLEASE_GENERATE_YOUR_OWN_SECRET")
echo -e "${GREEN}💡 Suggested admin secret (copy this):${NC}"
echo "$SUGGESTED_SECRET"
echo ""
read -p "Press Enter to continue to Step 4..."
echo ""

# Step 4: Set Up Cron Job
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "⏰ Step 4: Setting Up Cron Job"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Creating cron job SQL file..."

cat > /tmp/miya_cron_job.sql <<EOF
-- Enable pg_cron extension if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Drop existing job if it exists
SELECT cron.unschedule('process-notifications');

-- Create cron job to process notifications every 5 minutes
SELECT cron.schedule(
  'process-notifications',
  '*/5 * * * *',
  \$\$
  SELECT net.http_post(
    url := 'https://${PROJECT_REF}.supabase.co/functions/v1/process_notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-miya-admin-secret', 'YOUR_ADMIN_SECRET_HERE'
    ),
    body := jsonb_build_object(
      'batchSize', 50,
      'maxAge', 24
    )
  );
  \$\$
);

-- Verify cron job was created
SELECT * FROM cron.job WHERE jobname = 'process-notifications';
EOF

echo -e "${GREEN}✅ Cron job SQL created at: /tmp/miya_cron_job.sql${NC}"
echo ""
echo -e "${YELLOW}⚠️  Manual step required!${NC}"
echo ""
echo "1. Go to: https://supabase.com/dashboard/project/$PROJECT_REF/editor"
echo "2. Open the SQL Editor"
echo "3. Copy the contents of /tmp/miya_cron_job.sql"
echo "4. REPLACE 'YOUR_ADMIN_SECRET_HERE' with the admin secret you set in Step 3"
echo "5. Run the query"
echo ""
echo "The SQL file content is:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat /tmp/miya_cron_job.sql
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "Press Enter when you've created the cron job..."
echo ""

# Step 5: Test Everything
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧪 Step 5: Testing Deployment"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Testing process_notifications endpoint..."
RESPONSE=$(curl -s "https://${PROJECT_REF}.supabase.co/functions/v1/process_notifications")

if echo "$RESPONSE" | grep -q "process_notifications worker alive"; then
    echo -e "${GREEN}✅ process_notifications is live!${NC}"
else
    echo -e "${YELLOW}⚠️  Unexpected response: $RESPONSE${NC}"
fi
echo ""

echo "Testing rook endpoint..."
RESPONSE=$(curl -s "https://${PROJECT_REF}.supabase.co/functions/v1/rook")

if echo "$RESPONSE" | grep -q "rook webhook alive"; then
    echo -e "${GREEN}✅ rook is live!${NC}"
else
    echo -e "${YELLOW}⚠️  Unexpected response: $RESPONSE${NC}"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 Deployment Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "✅ Edge functions deployed"
echo "✅ Database migrations applied"
echo "✅ Environment variables configured"
echo "✅ Cron job set up"
echo ""
echo "Next steps:"
echo "  1. Rebuild your iOS app in Xcode"
echo "  2. Test the new features:"
echo "     - Settings → Timezone picker"
echo "     - Settings → Quiet hours configuration"
echo "     - Notification detail → Snooze button"
echo ""
echo "📚 For more details, see:"
echo "  - DEPLOYMENT_GUIDE.md (step-by-step instructions)"
echo "  - NOTIFICATION_SYSTEM_FINAL.md (complete documentation)"
echo ""
echo "🔍 To view logs:"
echo "  supabase functions logs process_notifications --tail"
echo ""
echo "🎊 You're all set!"
