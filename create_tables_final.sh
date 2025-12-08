#!/bin/bash
# Final script to create Miya Health tables in Supabase
# Uses psql to connect directly to the database

set -e

PROJECT_REF="xmfgdeyrpzpqptckmcbr"
DB_HOST="db.${PROJECT_REF}.supabase.co"
DB_USER="postgres"
DB_NAME="postgres"
DB_PORT="5432"
SQL_FILE="database_schema.sql"

echo "🚀 Miya Health Database Setup"
echo "=============================="
echo ""

# Check SQL file
if [ ! -f "$SQL_FILE" ]; then
    echo "❌ Error: $SQL_FILE not found"
    exit 1
fi

echo "✅ SQL file found"
echo ""

# Get password
if [ -z "$DB_PASSWORD" ]; then
    echo "📝 Database Password Required"
    echo "============================"
    echo ""
    echo "To get your database password:"
    echo "1. Go to: https://supabase.com/dashboard/project/$PROJECT_REF"
    echo "2. Click: Settings → Database"
    echo "3. Under 'Connection string', find the password"
    echo "   (It's in the URI: postgresql://postgres:[PASSWORD]@...)"
    echo ""
    echo "Enter database password (hidden):"
    read -s DB_PASSWORD
    echo ""
fi

# Build connection string
CONN_STRING="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

echo "🔄 Connecting to database..."
echo ""

# Test connection first
if ! psql "$CONN_STRING" -c "SELECT 1;" -q > /dev/null 2>&1; then
    echo "❌ Connection failed. Please check your password."
    exit 1
fi

echo "✅ Connected successfully!"
echo ""
echo "📤 Executing SQL to create tables..."
echo ""

# Execute SQL
if psql "$CONN_STRING" -f "$SQL_FILE" -q; then
    echo ""
    echo "✅ SUCCESS! All 6 tables created:"
    echo "   ✓ families"
    echo "   ✓ family_members"
    echo "   ✓ user_profiles"
    echo "   ✓ health_conditions"
    echo "   ✓ connected_wearables"
    echo "   ✓ privacy_settings"
    echo ""
    echo "🔍 Verify in Supabase Dashboard:"
    echo "   https://supabase.com/dashboard/project/$PROJECT_REF/editor"
    echo ""
else
    echo ""
    echo "❌ Error executing SQL"
    echo ""
    echo "💡 Alternative: Run SQL manually in Supabase Dashboard"
    echo "   1. Go to: https://supabase.com/dashboard/project/$PROJECT_REF"
    echo "   2. Click 'SQL Editor' → 'New query'"
    echo "   3. Copy contents of $SQL_FILE and paste"
    echo "   4. Click 'Run'"
    exit 1
fi


