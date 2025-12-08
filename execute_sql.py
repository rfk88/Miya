#!/usr/bin/env python3
"""
Execute SQL in Supabase using the Management API.
Requires service_role key from Supabase Settings → API
"""

import requests
import json
import sys
import os

SUPABASE_URL = "https://xmfgdeyrpzpqptckmcbr.supabase.co"
SERVICE_ROLE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

if not SERVICE_ROLE_KEY:
    print("❌ SUPABASE_SERVICE_ROLE_KEY not found")
    print("\nGet it from: Supabase Dashboard → Settings → API → service_role key")
    print("Then: export SUPABASE_SERVICE_ROLE_KEY='your-key'")
    sys.exit(1)

def execute_sql(sql_content):
    """Execute SQL via Supabase Management API"""
    # Supabase uses PostgREST which doesn't support arbitrary SQL
    # But we can try the management API endpoint
    url = f"{SUPABASE_URL}/rest/v1/rpc/exec_sql"
    
    headers = {
        "apikey": SERVICE_ROLE_KEY,
        "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
        "Content-Type": "application/json"
    }
    
    # Try different possible endpoints
    endpoints = [
        f"{SUPABASE_URL}/rest/v1/rpc/exec_sql",
        f"{SUPABASE_URL}/rest/v1/rpc/execute_sql",
        f"https://api.supabase.com/v1/projects/xmfgdeyrpzpqptckmcbr/database/query"
    ]
    
    for endpoint in endpoints:
        try:
            # Try as RPC function
            payload = {"query": sql_content}
            response = requests.post(endpoint, headers=headers, json=payload, timeout=30)
            
            if response.status_code in [200, 201, 204]:
                print(f"✅ SQL executed successfully via {endpoint}")
                return True
        except:
            continue
    
    print("❌ Could not execute SQL via API (Supabase restricts this for security)")
    return False

if __name__ == "__main__":
    with open("database_schema.sql", "r") as f:
        sql = f.read()
    
    if execute_sql(sql):
        print("✅ Tables created!")
    else:
        print("\n💡 Use Supabase Dashboard SQL Editor instead:")
        print("   https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr/sql/new")


