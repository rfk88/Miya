#!/bin/bash
# Script to create Miya Health database tables in Supabase
# Uses psql to connect directly to the database

set -e

SUPABASE_URL="xmfgdeyrpzpqptckmcbr.supabase.co"
SQL_FILE="database_schema.sql"

echo "📋 Miya Health Database Setup"
echo "=============================="
echo ""

# Check if SQL file exists
if [ ! -f "$SQL_FILE" ]; then
    echo "❌ Error: $SQL_FILE not found"
    exit 1
fi

echo "✅ SQL file found: $SQL_FILE"
echo ""

# Get database password
if [ -z "$SUPABASE_DB_PASSWORD" ]; then
    echo "⚠️  Database password not set in environment."
    echo ""
    echo "To get your database password:"
    echo "1. Go to: https://supabase.com/dashboard/project/$SUPABASE_URL"
    echo "2. Click Settings → Database"
    echo "3. Find 'Connection string' → 'URI' or 'Connection pooling'"
    echo "4. The password is in the connection string"
    echo ""
    echo "Then run:"
    echo "  export SUPABASE_DB_PASSWORD='your-password'"
    echo "  ./setup_database.sh"
    echo ""
    echo "Or enter it now (will not be saved):"
    read -s SUPABASE_DB_PASSWORD
    echo ""
fi

# Construct connection string
# Format: postgresql://postgres:[password]@db.[project-ref].supabase.co:5432/postgres
DB_HOST="db.$SUPABASE_URL"
DB_USER="postgres"
DB_NAME="postgres"
DB_PORT="5432"

CONNECTION_STRING="postgresql://$DB_USER:$SUPABASE_DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"

echo "🔄 Attempting to connect to database..."
echo ""

# Check if psql is available
if ! command -v psql &> /dev/null; then
    echo "❌ psql not found. Installing via Homebrew..."
    brew install postgresql@15 || brew install postgresql
fi

# Execute SQL
echo "📤 Executing SQL to create tables..."
echo ""

if psql "$CONNECTION_STRING" -f "$SQL_FILE" -q; then
    echo ""
    echo "✅ SUCCESS! All tables created."
    echo ""
    echo "Verify in Supabase Dashboard:"
    echo "  https://supabase.com/dashboard/project/$SUPABASE_URL/editor"
    echo ""
    echo "You should see these 6 tables:"
    echo "  - families"
    echo "  - family_members"
    echo "  - user_profiles"
    echo "  - health_conditions"
    echo "  - connected_wearables"
    echo "  - privacy_settings"
else
    echo ""
    echo "❌ Error executing SQL"
    echo ""
    echo "Alternative: Run SQL manually in Supabase Dashboard:"
    echo "1. Go to: https://supabase.com/dashboard/project/$SUPABASE_URL"
    echo "2. Click 'SQL Editor' → 'New query'"
    echo "3. Copy contents of $SQL_FILE"
    echo "4. Paste and click 'Run'"
    exit 1
fi


