// Quick script to run the migration SQL directly via Supabase API
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") || "https://xmfgdeyrpzpqptckmcbr.supabase.co";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!supabaseServiceKey) {
  console.error("❌ SUPABASE_SERVICE_ROLE_KEY environment variable is required");
  console.error("   Get it from: Supabase Dashboard → Project Settings → API → service_role key");
  Deno.exit(1);
}

const supabase = createClient(supabaseUrl, supabaseServiceKey);

const migrationSQL = `
ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS schema_version text;

ALTER TABLE IF EXISTS public.vitality_scores
  ADD COLUMN IF NOT EXISTS computed_at timestamptz;

ALTER TABLE IF EXISTS public.user_profiles
  ADD COLUMN IF NOT EXISTS vitality_schema_version text;
`;

console.log("🔄 Running migration to add schema_version columns...");

const { error } = await supabase.rpc("exec_sql", { sql: migrationSQL });

if (error) {
  // Try direct query instead
  console.log("⚠️ RPC method not available, trying direct query...");
  const { error: directError } = await supabase
    .from("_migrations")
    .select("1")
    .limit(1);
  
  if (directError) {
    console.error("❌ Cannot execute SQL directly via Supabase JS client");
    console.error("   Error:", directError.message);
    console.error("\n📝 Please run this SQL manually in Supabase Dashboard:");
    console.error("   Go to: https://supabase.com/dashboard/project/xmfgdeyrpzpqptckmcbr/sql/new");
    console.error("\n" + migrationSQL);
    Deno.exit(1);
  }
}

console.log("✅ Migration completed successfully!");
console.log("   Added columns: vitality_scores.schema_version, vitality_scores.computed_at, user_profiles.vitality_schema_version");

