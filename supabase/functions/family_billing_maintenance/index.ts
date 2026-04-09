import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST,OPTIONS,GET",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-miya-admin-secret",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRoleKey =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

function hoursUntil(ts: string): number {
  return (Date.parse(ts) - Date.now()) / (1000 * 60 * 60);
}

async function queueGraceReminders() {
  const { data: families, error } = await supabase
    .from("families")
    .select("id, billing_grace_until")
    .eq("billing_status", "grace_pending_new_owner")
    .is("billing_owner_user_id", null)
    .not("billing_grace_until", "is", null);

  if (error) {
    throw new Error(`Failed to fetch grace families: ${error.message}`);
  }

  let remindersQueued = 0;
  for (const fam of families ?? []) {
    const graceUntil = fam.billing_grace_until as string | null;
    if (!graceUntil) continue;
    const hoursLeft = hoursUntil(graceUntil);
    const shouldNotify = (hoursLeft <= 72 && hoursLeft > 48) || (hoursLeft <= 24 && hoursLeft > 0);
    if (!shouldNotify) continue;

    const reminderType = hoursLeft <= 24 ? "final_day" : "three_days_left";

    // Idempotency: skip if already queued same reminder in the last 24h.
    const { data: existing } = await supabase
      .from("notification_queue")
      .select("id")
      .eq("status", "pending")
      .contains("payload", { kind: "billing_grace_reminder", family_id: String(fam.id), reminder_type: reminderType })
      .limit(1);
    if ((existing ?? []).length > 0) continue;

    const { data: members, error: memErr } = await supabase
      .from("family_members")
      .select("user_id")
      .eq("family_id", fam.id)
      .eq("invite_status", "accepted")
      .not("user_id", "is", null);

    if (memErr) continue;
    const rows = (members ?? []).map((m: any) => ({
      recipient_user_id: m.user_id,
      member_user_id: m.user_id,
      alert_state_id: null,
      channel: "push",
      payload: {
        kind: "billing_grace_reminder",
        family_id: String(fam.id),
        grace_until: graceUntil,
        reminder_type: reminderType,
      },
      status: "pending",
    }));

    if (rows.length > 0) {
      const { error: insertErr } = await supabase.from("notification_queue").insert(rows);
      if (!insertErr) remindersQueued += rows.length;
    }
  }

  return remindersQueued;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method === "GET") {
    return jsonResponse({ ok: true, message: "family_billing_maintenance alive" });
  }
  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

  const raw = Deno.env.get("MIYA_ADMIN_SECRET");
  if (typeof raw !== "string" || raw.trim() === "") {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }
  const provided = req.headers.get("x-miya-admin-secret") ?? "";
  if (provided !== raw.trim()) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }

  try {
    const remindersQueued = await queueGraceReminders();
    const { data: expiredRows, error: expErr } = await supabase.rpc("expire_family_billing_grace");
    if (expErr) {
      return jsonResponse({ ok: false, error: expErr.message }, 500);
    }

    return jsonResponse({
      ok: true,
      reminders_queued: remindersQueued,
      families_expired: Number(expiredRows ?? 0),
    });
  } catch (error) {
    return jsonResponse(
      { ok: false, error: error instanceof Error ? error.message : "Unknown error" },
      500,
    );
  }
});
