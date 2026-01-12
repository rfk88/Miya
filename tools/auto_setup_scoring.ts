// Automated setup script for server-side scoring
// This will run the migration and set secrets automatically

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = "https://xmfgdeyrpzpqptckmcbr.supabase.co";
const serviceRoleKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtZmdkZXlycHpwcXB0Y2ttY2JyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDE2MDg2MywiZXhwIjoyMDc5NzM2ODYzfQ.0zHTKRpmY5kTIo25UxDAn8U6VNn29cmvYewRP75R0io";

const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
});

console.log("🚀 Setting up server-side scoring...\n");

// Step 1: Run migration
console.log("📝 Step 1: Adding migration columns...");
const migrationSQL = `
ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS schema_version text;

ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS computed_at timestamptz;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS vitality_schema_version text;
`;

// Use PostgREST to execute SQL (via a custom function or direct query)
// Since we can't execute raw SQL directly, we'll use the REST API
const { error: migrationError } = await supabase.rpc("exec_sql", {
  sql: migrationSQL,
});

if (migrationError) {
  // Fallback: Use direct SQL execution via fetch
  console.log("   Using direct SQL execution...");
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/exec_sql`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${serviceRoleKey}`,
    },
    body: JSON.stringify({ sql: migrationSQL }),
  });

  if (!response.ok) {
    console.log("   ⚠️  Cannot execute SQL automatically via API");
    console.log("   📋 Please run this SQL manually in Supabase Dashboard:");
    console.log("   https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr/sql/new\n");
    console.log(migrationSQL);
    console.log("\n   Then press Enter to continue...");
    await Deno.stdin.read(new Uint8Array(1));
  } else {
    console.log("   ✅ Migration columns added!");
  }
} else {
  console.log("   ✅ Migration columns added!");
}

// Step 2: Generate and set secret
console.log("\n🔐 Step 2: Setting Edge Function secret...");
const secret = crypto.randomUUID() + crypto.randomUUID().replace(/-/g, "");
console.log(`   Generated secret: ${secret.substring(0, 20)}...`);

// Use Supabase Management API to set secret
const { error: secretError } = await fetch(
  `https://api.supabase.com/v1/projects/xmfgdeyrpzpqptckmcbr/secrets`,
  {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${Deno.env.get("SUPABASE_ACCESS_TOKEN") || ""}`,
    },
    body: JSON.stringify({
      name: "MIYA_ADMIN_SECRET",
      value: secret,
    }),
  }
).then((r) => r.json());

if (secretError || !Deno.env.get("SUPABASE_ACCESS_TOKEN")) {
  console.log("   ⚠️  Cannot set secret automatically (need SUPABASE_ACCESS_TOKEN)");
  console.log("   📋 Please set it manually:");
  console.log("   1. Go to: https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr/settings/functions");
  console.log("   2. Add secret: MIYA_ADMIN_SECRET");
  console.log(`   3. Value: ${secret}`);
  console.log("\n   Then press Enter to continue...");
  await Deno.stdin.read(new Uint8Array(1));
} else {
  console.log("   ✅ Secret set!");
}

console.log("\n📦 Step 3: Deploying Edge Functions...");
console.log("   Run these commands:");
console.log("   supabase functions deploy rook --project-ref xmfgdeyrpzpqptckmcbr");
console.log("   supabase functions deploy recompute_vitality_scores --project-ref xmfgdeyrpzpqptckmcbr");

console.log("\n✅ Setup instructions complete!");
console.log("   After deploying functions, server-side scoring will be active.");

