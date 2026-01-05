#!/usr/bin/env python3
"""
Diagnose the save name issue by querying Supabase family_members table
"""

import requests
import json

SUPABASE_URL = "https://xmfgdeyrpzpqptckmcbr.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtZmdkZXlycHpwcXB0Y2ttY2JyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQxNjA4NjMsImV4cCI6MjA3OTczNjg2M30.zL4PS7grZF3BJUcdgGmJMa_2KTsl-1fCMbaCyhUqSIA"

headers = {
    "apikey": SUPABASE_ANON_KEY,
    "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
    "Content-Type": "application/json"
}

print("🔍 Connecting to Supabase...")
print("\n📋 Querying family_members table...")
try:
    response = requests.get(
        f"{SUPABASE_URL}/rest/v1/family_members",
        headers=headers,
        params={"select": "*"}
    )
    response.raise_for_status()
    members = response.json()
    
    print(f"\n✅ Found {len(members)} family member(s):\n")
    
    for i, member in enumerate(members, 1):
        print(f"Member {i}:")
        print(f"  id: {member.get('id')}")
        print(f"  user_id: {member.get('user_id')}")
        print(f"  family_id: {member.get('family_id')}")
        print(f"  first_name: {member.get('first_name')}")
        print(f"  role: {member.get('role')}")
        print(f"  invite_status: {member.get('invite_status')}")
        print()
    
    # Check for potential issues
    print("\n🔍 DIAGNOSIS:")
    print("=" * 50)
    
    # Check if any member has null user_id or family_id
    null_user_ids = [m for m in members if m.get('user_id') is None]
    null_family_ids = [m for m in members if m.get('family_id') is None]
    
    if null_user_ids:
        print(f"⚠️  Found {len(null_user_ids)} member(s) with NULL user_id")
        for m in null_user_ids:
            print(f"   - id: {m.get('id')}, name: {m.get('first_name')}")
    
    if null_family_ids:
        print(f"⚠️  Found {len(null_family_ids)} member(s) with NULL family_id")
        for m in null_family_ids:
            print(f"   - id: {m.get('id')}, name: {m.get('first_name')}")
    
    # Check data types
    print("\n📊 Column Types Check:")
    if members:
        sample = members[0]
        print(f"  id type: {type(sample.get('id'))}")
        print(f"  user_id type: {type(sample.get('user_id'))}")
        print(f"  family_id type: {type(sample.get('family_id'))}")
        print(f"  first_name type: {type(sample.get('first_name'))}")
    
    # Check what the update query would match
    print("\n🎯 What updateMyMemberName would match:")
    print("   (Looking for rows where user_id AND family_id match)")
    
    # Get unique user_ids and family_ids
    user_ids = set(m.get('user_id') for m in members if m.get('user_id'))
    family_ids = set(m.get('family_id') for m in members if m.get('family_id'))
    
    print(f"   Unique user_ids: {len(user_ids)}")
    print(f"   Unique family_ids: {len(family_ids)}")
    
    # Check if there are members with matching user_id AND family_id
    matches = []
    for member in members:
        uid = member.get('user_id')
        fid = member.get('family_id')
        if uid and fid:
            matches.append((uid, fid, member.get('id'), member.get('first_name')))
    
    print(f"\n   Members with both user_id AND family_id: {len(matches)}")
    for uid, fid, mid, name in matches:
        print(f"     - user_id: {uid}, family_id: {fid}, name: {name}")
    
except Exception as e:
    print(f"\n❌ Error querying database: {e}")
    print(f"   Error type: {type(e).__name__}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

