#!/usr/bin/env python3
"""
Script to create Miya Health database tables in Supabase.
Uses Supabase Management API to execute SQL.
"""

import requests
import json
import sys
import os

# Supabase configuration
SUPABASE_URL = "https://xmfgdeyrpzpqptckmcbr.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtZmdkZXlycHpwcXB0Y2ttY2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxNjA4NjMsImV4cCI6MjA3OTczNjg2M30.zL4PS7grZF3BJUcdgGmJMa_2KTsl-1fCMbaCyhUqSIA"

# Get service_role key from environment or user input
SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

if not SERVICE_ROLE_KEY:
    print("⚠️  SERVICE_ROLE_KEY not found in environment.")
    print("Please get your service_role key from:")
    print("   Supabase Dashboard → Settings → API → service_role key")
    print("\nThen run:")
    print("   export SUPABASE_SERVICE_ROLE_KEY='your-service-role-key'")
    print("   python3 create_tables.py")
    sys.exit(1)

def execute_sql_via_management_api(sql_content):
    """Execute SQL using Supabase Management API"""
    # Supabase Management API endpoint for SQL execution
    # Note: This might require the project's access token instead
    url = f"{SUPABASE_URL}/rest/v1/rpc/exec_sql"
    
    headers = {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Content-Type": "application/json"
    }
    
    payload = {
        "query": sql_content
    }
    
    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        
        if response.status_code == 200 or response.status_code == 201:
            print("✅ SQL executed successfully!")
            return True
        else:
            print(f"❌ Error: {response.status_code}")
            print(f"Response: {response.text}")
            return False
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Network error: {e}")
        return False

def execute_sql_via_postgrest(sql_content):
    """Alternative: Try using PostgREST directly"""
    # Split SQL into individual statements
    statements = [s.strip() for s in sql_content.split(';') if s.strip() and not s.strip().startswith('--')]
    
    print(f"📋 Found {len(statements)} SQL statements to execute")
    
    # Unfortunately, PostgREST doesn't support arbitrary SQL execution
    # We need to use the Supabase Dashboard or CLI
    print("❌ Direct SQL execution via API is not supported by Supabase for security reasons.")
    print("✅ Please use the Supabase Dashboard SQL Editor instead.")
    return False

if __name__ == "__main__":
    sql_file = "database_schema.sql"
    
    try:
        with open(sql_file, 'r') as f:
            sql_content = f.read()
        
        print("📋 SQL file loaded successfully")
        print(f"📏 SQL content: {len(sql_content)} characters")
        print("\n⚠️  Note: Supabase doesn't allow arbitrary SQL execution via REST API.")
        print("   This is a security feature.")
        print("\n✅ RECOMMENDED: Use Supabase Dashboard SQL Editor")
        print("   1. Go to: https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr")
        print("   2. Click 'SQL Editor' → 'New query'")
        print("   3. Paste the SQL and click 'Run'")
        print("\n🔄 Attempting alternative method...")
        
        # Try the management API approach
        success = execute_sql_via_management_api(sql_content)
        
        if not success:
            print("\n💡 The SQL must be executed manually in the Supabase Dashboard.")
            print("   This is the standard and secure way to create tables.")
        
    except FileNotFoundError:
        print(f"❌ Error: {sql_file} not found")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


