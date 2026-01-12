#!/bin/bash

# Quick cache clear script

echo "🗑️  Clearing AI insight cache..."

# Use Python to execute the SQL
python3 << 'EOF'
import os
from supabase import create_client

url = os.environ.get("SUPABASE_URL", "https://xmfgdeyrpzpqptckmcbr.supabase.co")
# Need service role key for this
service_key = input("Enter your Supabase Service Role Key (from dashboard): ")

supabase = create_client(url, service_key)

# Clear this specific cached insight
alert_id = "6a4b42d3-2be9-4bcf-ab70-6cc2a31d37d8"
result = supabase.table("pattern_alert_ai_insights").delete().eq("alert_state_id", alert_id).execute()

print(f"✅ Cleared cache for alert {alert_id}")
print(f"   Deleted {len(result.data) if result.data else 0} cached insights")
EOF

echo ""
echo "✅ Cache cleared! Now reload the app and the insight will regenerate with the new format."
