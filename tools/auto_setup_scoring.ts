// Automated setup script for server-side scoring
// This will run the migration and set secrets automatically

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Load configuration from environment variables
// Supports both Deno and Node.js environments
const getEnvVar = (key: string): string => {
  const value = typeof Deno !== "undefined" 
    ? Deno.env.get(key) 
    : typeof process !== "undefined" 
      ? process.env[key] 
      : undefined;
  
  if (!value) {
    throw new Error(
      `Missing required environment variable: ${key}\n` +
      `Please set it before running this script.\n` +
      `Example: ${key}=your_value deno run -A tools/auto_setup_scoring.ts`
    );
  }
  
  return value;
};

const supabaseUrl = getEnvVar("SUPABASE_URL");
const serviceRoleKey = getEnvVar("SUPABASE_SERVICE_ROLE_KEY");

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
    const projectRef = supabaseUrl.match(/https:\/\/([^.]+)\.supabase\.co/)?.[1] || "YOUR_PROJECT_REF";
    console.log("   ⚠️  Cannot execute SQL automatically via API");
    console.log("   📋 Please run this SQL manually in Supabase Dashboard:");
    console.log(`   https://supabase.com/dashboard/project/${projectRef}/sql/new\n`);
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
const projectRef = supabaseUrl.match(/https:\/\/([^.]+)\.supabase\.co/)?.[1] || "YOUR_PROJECT_REF";
const accessToken = typeof Deno !== "undefined" 
  ? Deno.env.get("SUPABASE_ACCESS_TOKEN")
  : typeof process !== "undefined"
    ? process.env.SUPABASE_ACCESS_TOKEN
    : undefined;

const { error: secretError } = await fetch(
  `https://api.supabase.com/v1/projects/${projectRef}/secrets`,
  {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${accessToken || ""}`,
    },
    body: JSON.stringify({
      name: "MIYA_ADMIN_SECRET",
      value: secret,
    }),
  }
).then((r) => r.json());

if (secretError || !accessToken) {
  console.log("   ⚠️  Cannot set secret automatically (need SUPABASE_ACCESS_TOKEN)");
  console.log("   📋 Please set it manually:");
  console.log(`   1. Go to: https://supabase.com/dashboard/project/${projectRef}/settings/functions`);
  console.log("   2. Add secret: MIYA_ADMIN_SECRET");
  console.log(`   3. Value: ${secret}`);
  console.log("\n   Then press Enter to continue...");
  await Deno.stdin.read(new Uint8Array(1));
} else {
  console.log("   ✅ Secret set!");
}

console.log("\n📦 Step 3: Deploying Edge Functions...");
console.log("   Run these commands:");
console.log(`   supabase functions deploy rook --project-ref ${projectRef}`);
console.log(`   supabase functions deploy recompute_vitality_scores --project-ref ${projectRef}`);

console.log("\n✅ Setup instructions complete!");
console.log("   After deploying functions, server-side scoring will be active.");

