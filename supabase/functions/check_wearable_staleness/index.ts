/**
 * Check Wearable Staleness — Producer for missing wearable notifications.
 * Detects members whose last wearable sync is >= 3 days (warning) or >= 7 days (critical),
 * resolves caregivers (superadmin/admin) per family, dedupes against recent queue rows,
 * and inserts into notification_queue so process_notifications can deliver push (etc.).
 *
 * Invoke via cron (e.g. daily 06:00 UTC) with x-miya-admin-secret.
 */

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

function toYYYYMMDD(d: Date): string {
  return d.toISOString().slice(0, 10);
}

/** Days between two YYYY-MM-DD dates (end - start). */
function daysBetween(startDateStr: string, endDateStr: string): number {
  const start = new Date(startDateStr + "T00:00:00Z");
  const end = new Date(endDateStr + "T00:00:00Z");
  const ms = end.getTime() - start.getTime();
  return Math.floor(ms / (24 * 60 * 60 * 1000));
}

/**
 * Get caregiver recipient user IDs for a member (same family, role in superadmin/admin, invite_status accepted).
 * Only returns admins; excludes the member themselves so we notify caregivers only.
 */
async function fetchCaregiverRecipients(
  supabaseClient: any,
  memberUserId: string,
): Promise<string[]> {
  const { data: fm, error: fmErr } = await supabaseClient
    .from("family_members")
    .select("family_id")
    .eq("user_id", memberUserId)
    .maybeSingle();
  if (fmErr || !fm?.family_id) return [];

  const familyId = fm.family_id;
  const { data: admins, error: aErr } = await supabaseClient
    .from("family_members")
    .select("user_id,role,invite_status")
    .eq("family_id", familyId)
    .in("role", ["superadmin", "admin"])
    .eq("invite_status", "accepted");
  if (aErr) return [];

  const ids = (admins ?? [])
    .map((r: any) => String(r.user_id))
    .filter((x) => x && x !== "null" && x !== memberUserId);
  return Array.from(new Set(ids));
}

/**
 * Check if we already have a recent pending/sent missing_wearable notification for this member and threshold.
 */
async function hasRecentMissingWearableNotification(
  supabaseClient: any,
  memberUserId: string,
  daysStale: 3 | 7,
): Promise<boolean> {
  const now = new Date();
  const cutoff =
    daysStale === 3
      ? new Date(now.getTime() - 24 * 60 * 60 * 1000)
      : new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const cutoffIso = cutoff.toISOString();

  const { data: rows, error } = await supabaseClient
    .from("notification_queue")
    .select("id")
    .eq("member_user_id", memberUserId)
    .in("status", ["pending", "sent"])
    .gte("created_at", cutoffIso)
    .limit(1);

  if (error || !rows?.length) return false;
  // We need to filter by payload.kind and payload.days_stale; Supabase JS may not support jsonb filters on all plans.
  // So fetch a few rows and filter in memory, or use RPC. Use a small limit and filter client-side.
  const { data: allRows } = await supabaseClient
    .from("notification_queue")
    .select("id, payload")
    .eq("member_user_id", memberUserId)
    .in("status", ["pending", "sent"])
    .gte("created_at", cutoffIso)
    .limit(20);

  const match = (allRows ?? []).find(
    (r: any) =>
      r?.payload?.kind === "missing_wearable" && Number(r?.payload?.days_stale) === daysStale,
  );
  return !!match;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method === "GET") {
    return jsonResponse({ ok: true, message: "check_wearable_staleness alive" });
  }

  if (req.method !== "POST") {
    return jsonResponse({ ok: false, error: "Method not allowed" }, 405);
  }

  // Strict admin secret: reject when not configured (missing, non-string, or empty/whitespace).
  const raw = Deno.env.get("MIYA_ADMIN_SECRET");
  if (typeof raw !== "string" || raw.trim() === "") {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }
  const expected = raw.trim();
  const provided = req.headers.get("x-miya-admin-secret") ?? "";
  if (provided !== expected) {
    return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
  }

  const todayStr = toYYYYMMDD(new Date());
  const stats = { staleMembers: 0, recipientsResolved: 0, rowsInserted: 0, skippedDedupe: 0, errors: 0 };

  try {
    // 1) Last sync from wearable_daily_metrics (primary): MAX(metric_date) per user_id.
    // Order by metric_date desc so first occurrence per user_id is their latest date.
    const { data: metricRows, error: metricErr } = await supabase
      .from("wearable_daily_metrics")
      .select("user_id, metric_date")
      .not("user_id", "is", null)
      .order("metric_date", { ascending: false })
      .limit(100000);
    if (metricErr) {
      console.error("check_wearable_staleness: wearable_daily_metrics fetch failed", metricErr);
      return jsonResponse({ ok: false, error: metricErr.message }, 500);
    }

    const lastMetricDateByUser = new Map<string, string>();
    for (const r of metricRows ?? []) {
      const uid = r.user_id as string;
      if (lastMetricDateByUser.has(uid)) continue; // already have latest for this user (we ordered desc)
      lastMetricDateByUser.set(uid, String(r.metric_date));
    }

    // 2) Fallback: family_members with user_id that we care about; get vitality_score_updated_at from user_profiles for users not in lastMetricDateByUser or to fill in missing
    const { data: allFamilyMembers, error: fmErr } = await supabase
      .from("family_members")
      .select("user_id, family_id, first_name")
      .not("user_id", "is", null)
      .eq("invite_status", "accepted");
    if (fmErr) {
      console.error("check_wearable_staleness: family_members fetch failed", fmErr);
      return jsonResponse({ ok: false, error: fmErr.message }, 500);
    }

    const memberUserIds = Array.from(new Set((allFamilyMembers ?? []).map((r: any) => r.user_id)));
    const { data: profiles, error: profErr } = await supabase
      .from("user_profiles")
      .select("user_id, vitality_score_updated_at")
      .in("user_id", memberUserIds);
    if (profErr) {
      console.error("check_wearable_staleness: user_profiles fetch failed", profErr);
      return jsonResponse({ ok: false, error: profErr.message }, 500);
    }

    const profileUpdatedAtByUser = new Map<string, string>();
    for (const p of profiles ?? []) {
      const t = (p as any).vitality_score_updated_at;
      if (t) profileUpdatedAtByUser.set((p as any).user_id, t.slice(0, 10));
    }

    const firstNameByUser = new Map<string, string>();
    for (const fm of allFamilyMembers ?? []) {
      const u = (fm as any).user_id;
      const name = (fm as any).first_name;
      if (u && name) firstNameByUser.set(u, name);
    }

    // 3) Effective last sync per user: prefer lastMetricDateByUser, else date part of vitality_score_updated_at
    const lastSyncDateByUser = new Map<string, string>();
    for (const uid of memberUserIds) {
      const metricDate = lastMetricDateByUser.get(uid);
      if (metricDate) {
        lastSyncDateByUser.set(uid, metricDate);
        continue;
      }
      const profileAt = profileUpdatedAtByUser.get(uid);
      if (profileAt) lastSyncDateByUser.set(uid, profileAt);
      // If neither: no data yet — do not notify (plan: do not enqueue)
    }

    // 4) Stale members: days_stale >= 3. Use only 7-day if >= 7 to avoid two notifications.
    const staleMembers: Array<{ memberUserId: string; daysStale: number; memberName: string }> = [];
    for (const [userId, lastSync] of lastSyncDateByUser) {
      const daysStale = daysBetween(lastSync, todayStr);
      if (daysStale < 3) continue;
      const memberName = firstNameByUser.get(userId) ?? "Family member";
      staleMembers.push({
        memberUserId: userId,
        daysStale,
        memberName,
      });
    }
    stats.staleMembers = staleMembers.length;

    const toInsert: Array<{
      recipient_user_id: string;
      member_user_id: string;
      alert_state_id: null;
      channel: string;
      payload: Record<string, unknown>;
      status: string;
    }> = [];

    for (const { memberUserId, daysStale, memberName } of staleMembers) {
      const threshold: 3 | 7 = daysStale >= 7 ? 7 : 3;
      const severity = threshold === 7 ? "critical" : "watch";

      const alreadySent = await hasRecentMissingWearableNotification(supabase, memberUserId, threshold);
      if (alreadySent) {
        stats.skippedDedupe++;
        continue;
      }

      const recipients = await fetchCaregiverRecipients(supabase, memberUserId);
      if (recipients.length === 0) continue;
      stats.recipientsResolved += recipients.length;

      const payload = {
        kind: "missing_wearable",
        member_user_id: memberUserId,
        days_stale: threshold,
        severity,
        member_name: memberName,
      };

      for (const recipientUserId of recipients) {
        toInsert.push({
          recipient_user_id: recipientUserId,
          member_user_id: memberUserId,
          alert_state_id: null,
          channel: "push",
          payload,
          status: "pending",
        });
      }
    }

    if (toInsert.length > 0) {
      const { error: insertErr } = await supabase.from("notification_queue").insert(toInsert);
      if (insertErr) {
        console.error("check_wearable_staleness: notification_queue insert failed", insertErr);
        stats.errors++;
        return jsonResponse({
          ok: false,
          error: insertErr.message,
          stats: { ...stats, rowsInserted: 0 },
        }, 500);
      }
      stats.rowsInserted = toInsert.length;
    }

    console.log("check_wearable_staleness: done", stats);
    return jsonResponse({ ok: true, stats });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("check_wearable_staleness: error", message);
    return jsonResponse({ ok: false, error: message, stats }, 500);
  }
});
