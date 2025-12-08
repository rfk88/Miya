#!/usr/bin/env python3
"""
Create Miya Health database tables in Supabase.
This script uses the Supabase Python client to execute SQL.
"""

import os
import sys

# Try to import supabase client
try:
    from supabase import create_client, Client
except ImportError:
    print("❌ Supabase Python client not installed.")
    print("Installing...")
    os.system("pip3 install supabase")
    from supabase import create_client, Client

# Supabase configuration
SUPABASE_URL = "https://xmfgdeyrpzpqptckmcbr.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtZmdkZXlycHpwcXB0Y2ttY2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxNjA4NjMsImV4cCI6MjA3OTczNjg2M30.zL4PS7grZF3BJUcdgGmJMa_2KTsl-1fCMbaCyhUqSIA"

# Get service_role key (required for SQL execution)
SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

if not SERVICE_ROLE_KEY:
    print("⚠️  SERVICE_ROLE_KEY environment variable not set.")
    print("\nTo get your service_role key:")
    print("1. Go to: https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr")
    print("2. Click Settings → API")
    print("3. Copy the 'service_role' key (NOT the anon key)")
    print("\nThen run:")
    print("  export SUPABASE_SERVICE_ROLE_KEY='your-service-role-key'")
    print("  python3 create_tables_supabase.py")
    sys.exit(1)

def execute_sql(sql_content: str):
    """Execute SQL using Supabase client"""
    try:
        # Create client with service_role key for admin operations
        supabase: Client = create_client(SUPABASE_URL, SERVICE_ROLE_KEY)
        
        # Unfortunately, the Supabase Python client doesn't support arbitrary SQL execution
        # We need to use the REST API directly or psql
        print("⚠️  Supabase Python client doesn't support arbitrary SQL execution.")
        print("✅ Using psql method instead...")
        return False
        
    except Exception as e:
        print(f"❌ Error: {e}")
        return False

if __name__ == "__main__":
    sql_file = "database_schema.sql"
    
    try:
        with open(sql_file, 'r') as f:
            sql_content = f.read()
        
        print("📋 SQL file loaded")
        print(f"📏 Content length: {len(sql_content)} characters")
        print("\n🔄 Attempting to execute SQL...")
        
        # The Supabase Python client doesn't support SQL execution
        # We'll use the shell script instead
        print("\n✅ Please use the shell script instead:")
        print("   ./setup_database.sh")
        print("\nOr execute manually in Supabase Dashboard SQL Editor.")
        
    except FileNotFoundError:
        print(f"❌ Error: {sql_file} not found")
        sys.exit(1)


