// Notification Queue Worker
// Processes pending notifications from notification_queue table
// Respects user preferences, quiet hours, and snooze settings

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST,OPTIONS,GET",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey, x-miya-admin-secret",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceRoleKey);

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// Check if current time is within user's quiet hours
function isInQuietHours(
  quietStart: string | null,
  quietEnd: string | null,
  userTimezone: string | null,
): boolean {
  if (!quietStart || !quietEnd) return false;

  try {
    const now = new Date();
    const timezone = userTimezone || "UTC";

    // Get current time in user's timezone
    const userTime = new Intl.DateTimeFormat("en-US", {
      timeZone: timezone,
      hour: "2-digit",
      minute: "2-digit",
      hour12: false,
    }).format(now);

    const [currentHour, currentMinute] = userTime.split(":").map(Number);
    const currentMinutes = currentHour * 60 + currentMinute;

    // Parse quiet hours (format: "HH:MM:SS" or "HH:MM")
    const parseTime = (time: string): number => {
      const parts = time.split(":");
      const hour = parseInt(parts[0] || "0");
      const minute = parseInt(parts[1] || "0");
      return hour * 60 + minute;
    };

    const startMinutes = parseTime(quietStart);
    const endMinutes = parseTime(quietEnd);

    // Handle quiet hours that span midnight
    if (startMinutes > endMinutes) {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    } else {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    }
  } catch (error) {
    console.error("Error checking quiet hours:", error);
    return false;
  }
}

// Determine if notification should be sent based on user preferences
async function shouldSendNotification(
  recipientUserId: string,
  alertStateId: string | null,
  severity: string,
): Promise<{ shouldSend: boolean; reason?: string }> {
  try {
    // Fetch user preferences
    const { data: profile, error: profileErr } = await supabase
      .from("user_profiles")
      .select(
        "notify_push, quiet_hours_start, quiet_hours_end, quiet_hours_notification_level, timezone",
      )
      .eq("user_id", recipientUserId)
      .maybeSingle();

    if (profileErr) {
      console.error("Error fetching user profile:", profileErr);
      return { shouldSend: false, reason: "profile_fetch_error" };
    }

    if (!profile) {
      return { shouldSend: false, reason: "profile_not_found" };
    }

    // Check if user has push notifications enabled
    if (!profile.notify_push) {
      return { shouldSend: false, reason: "push_disabled" };
    }

    // Check if alert is dismissed or snoozed FOR THIS RECIPIENT
    if (alertStateId) {
      const { data: alert, error: alertErr } = await supabase
        .from("pattern_alert_state")
        .select("dismissed_at")
        .eq("id", alertStateId)
        .maybeSingle();

      if (alertErr) {
        console.error("Error fetching alert state:", alertErr);
      } else if (alert) {
        if (alert.dismissed_at) {
          return { shouldSend: false, reason: "alert_dismissed" };
        }

        // Check if THIS USER has snoozed this alert
        const { data: snooze, error: snoozeErr } = await supabase
          .from("alert_snoozes")
          .select("snoozed_until")
          .eq("alert_id", alertStateId)
          .eq("user_id", recipientUserId)  // Per-user snooze check!
          .maybeSingle();

        if (snoozeErr) {
          console.error("Error fetching snooze state:", snoozeErr);
        } else if (snooze?.snoozed_until) {
          const snoozeUntil = new Date(snooze.snoozed_until);
          if (snoozeUntil > new Date()) {
            return { shouldSend: false, reason: "alert_snoozed" };
          }
        }
      }
    }

    // Check quiet hours
    const inQuietHours = isInQuietHours(
      profile.quiet_hours_start,
      profile.quiet_hours_end,
      profile.timezone,
    );

    if (inQuietHours) {
      const quietLevel = profile.quiet_hours_notification_level || "none";

      // none: Don't send any notifications during quiet hours
      if (quietLevel === "none") {
        return { shouldSend: false, reason: "quiet_hours_none" };
      }

      // critical_only: Only send critical notifications during quiet hours
      if (quietLevel === "critical_only") {
        if (severity !== "critical") {
          return { shouldSend: false, reason: "quiet_hours_not_critical" };
        }
      }

      // all: Send all notifications even during quiet hours (fallthrough)
    }

    return { shouldSend: true };
  } catch (error) {
    console.error("Error in shouldSendNotification:", error);
    return { shouldSend: false, reason: "unknown_error" };
  }
}

// ── APNs JWT ─────────────────────────────────────────────────────────────────
// JWT tokens are valid for 1 hour; we cache and reuse within a single worker run.
let _cachedApnsJwt: { token: string; exp: number } | null = null;

async function getApnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (_cachedApnsJwt && now < _cachedApnsJwt.exp) return _cachedApnsJwt.token;

  const keyId = Deno.env.get("APNS_KEY_ID")!;
  const teamId = Deno.env.get("APNS_TEAM_ID")!;
  const pem = Deno.env.get("APNS_PRIVATE_KEY")!;

  // Strip PEM headers and decode to DER bytes
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const keyDer = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyDer,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const b64url = (obj: unknown) =>
    btoa(JSON.stringify(obj)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const header = b64url({ alg: "ES256", kid: keyId });
  const jwtPayload = b64url({ iss: teamId, iat: now });
  const signingInput = `${header}.${jwtPayload}`;

  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );

  const sigB64url = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");

  const jwt = `${signingInput}.${sigB64url}`;
  _cachedApnsJwt = { token: jwt, exp: now + 50 * 60 }; // Refresh 10 min before expiry
  return jwt;
}

// ── Notification content builder (warm tone; descriptive vs personal baseline only) ──

function formatMetric(metric: string): string {
  const map: Record<string, string> = {
    sleep_minutes: "sleep duration",
    steps: "step count",
    hrv_ms: "HRV",
    resting_hr: "resting heart rate",
    sleep_efficiency_pct: "sleep efficiency",
    movement_minutes: "active minutes",
    deep_sleep_minutes: "deep sleep",
  };
  return map[metric] ?? metric.replace(/_/g, " ");
}

function formatPillar(pillar: string): string {
  const map: Record<string, string> = {
    sleep: "Sleep",
    movement: "Movement",
    stress: "Stress",
    heart: "Heart Health",
    nutrition: "Nutrition",
  };
  return map[pillar] ?? pillar;
}

// Display label for a competitive-challenge focus key (mirrors ChallengeFocus.displayName on iOS).
function formatCompetitiveFocus(focus: string): string {
  const map: Record<string, string> = {
    sleep: "Sleep",
    movement: "Activity",
    stress: "Recovery",
    steps: "Steps",
  };
  return map[focus] ?? "Challenge";
}

function driftBand(payload: any): "moderate" | "marked" {
  const p = payload.deviation_percent;
  if (p == null || typeof p !== "number" || !Number.isFinite(p)) return "moderate";
  return Math.abs(p) >= 0.18 ? "marked" : "moderate";
}

/** False only when enqueue omitted other family recipients (e.g. subject's settings). Missing = legacy rows, treat as true. */
function familyNotifiedInApp(payload: any): boolean {
  return payload.family_notified_in_app !== false;
}

/** Pattern-alert copy: member vs family_lead (other family members in Miya), stage level, drift. */
function buildPatternAlertCopy(payload: any, memberFirst: string): { title: string; body: string } | null {
  const level = Number(payload.level ?? 3);
  const band = driftBand(payload);
  const audience = (payload.audience as string) || "member";
  /** True when no other accepted family members on Miya to notify (solo in family on the app). */
  const sole = payload.sole_in_app_family_lead === true;
  const notifiedFamilyInApp = familyNotifiedInApp(payload);
  const metric = formatMetric(payload.metric_type ?? "");

  if (audience === "family_lead") {
    if (level < 7) return null;
    const t = (modTitle: string, markTitle: string, modBody: string, markBody: string) =>
      band === "marked" ? { title: markTitle, body: markBody } : { title: modTitle, body: modBody };
    if (level === 7) {
      return t(
        `${memberFirst}: ${metric} low about a week`,
        `${memberFirst}: ${metric} sharply down ~1 week`,
        `A little under their norm—life gets busy. A warm “how are you, really?” goes further than pressure.`,
        `Well below what’s usual for them. Show up with care; encourage rest and a chat with their doctor if they’re not feeling great.`,
      );
    }
    if (level === 14) {
      return t(
        `${memberFirst}: ${metric} off pattern ~2 weeks`,
        `${memberFirst}: large ${metric} gap ~2 weeks`,
        `A gentler dip that’s lingered—your steady presence helps them feel supported, not watched.`,
        `A meaningful change for them. Extra kindness and help accessing care if they want it can make a real difference.`,
      );
    }
    return t(
      `${memberFirst}: ${metric} still off ~3 weeks`,
      `${memberFirst}: please offer extra support`,
      `Worth sitting down kindly and planning together—accountability with heart, not shame.`,
      `${metric.charAt(0).toUpperCase() + metric.slice(1)} has been far below their baseline for three weeks. They may need you—and maybe a clinician—on their side. Show up softly, stay close.`,
    );
  }

  // Member audience — stage 3
  const mt = String(payload.metric_type ?? "");
  const sleepish = mt.includes("sleep");
  if (level === 3) {
    if (band === "marked") {
      return {
        title: `Your ${metric} is well below your normal`,
        body: sleepish
          ? `This is a bigger gap than usual for you. Be gentle with yourself—rest more if you can, and talk to someone you trust or your doctor if you’re worried.`
          : `This is a bigger gap than usual for you. Be gentle with yourself, and talk to someone you trust or your doctor if you’re worried.`,
      };
    }
    return {
      title: `Your ${metric} is a little under your usual`,
      body: sleepish
        ? `Last few nights trail your normal—that’s okay. When you have a moment, a little extra rest or routine tweak might help.`
        : `Your recent readings are a bit below your usual—that’s okay. Small tweaks or rest might help when you’re ready.`,
    };
  }

  if (level === 7) {
    if (sole) {
      return band === "marked"
        ? {
          title: `1 week: ${metric} far below normal`,
          body:
            `A week of a large gap vs your usual—we care about you. You’re the only person in your family on Miya right now, so no one else got this alert in the app. Reach out to someone you trust in real life if it helps, and seek care if you don’t feel right.`,
        }
        : {
          title: `1 week: ${metric} still low`,
          body:
            `Still under your baseline, and that’s been a week—totally human. You’re the only one in your family on Miya at the moment; reach out to someone you trust outside the app when you’re ready.`,
        };
    }
    if (!notifiedFamilyInApp) {
      return band === "marked"
        ? {
          title: `1 week: ${metric} far below normal`,
          body:
            `A week of a large gap vs your usual—we care about you. Based on your notification preferences, we didn’t alert others in your family in the app. Reach out to someone you trust if it helps, and seek care if you don’t feel right.`,
        }
        : {
          title: `1 week: ${metric} still low`,
          body:
            `Still under your baseline, and that’s been a week—totally human. You’ve chosen not to loop in your family on Miya for this—when you’re ready, people you trust outside the app can still help.`,
        };
    }
    return band === "marked"
      ? {
        title: `1 week: ${metric} far below normal`,
        body:
          `A week of a large gap vs your usual—we care about you. Everyone else in your family on Miya has been notified so they can check in with you.`,
      }
      : {
        title: `1 week: ${metric} still low`,
        body:
          `Still under your baseline, and that’s been a week—totally human. Your family on Miya is in the loop; reach out when you’re ready.`,
      };
  }
  if (level === 14) {
    if (sole) {
      return band === "marked"
        ? {
          title: `2 weeks: big ${metric} change`,
          body:
            `A sustained big change is worth taking seriously—for your wellbeing. You’re the only person in your family on Miya, so lean on people you trust outside the app; professional support is okay to ask for too.`,
        }
        : {
          title: `2 weeks: ${metric} off your pattern`,
          body:
            `Two weeks counts as a stretch. You’re the only one in your family on Miya right now—small steps still matter, and you’re not failing anyone.`,
        };
    }
    if (!notifiedFamilyInApp) {
      return band === "marked"
        ? {
          title: `2 weeks: big ${metric} drop`,
          body:
            `A sustained big change is worth taking seriously—for your wellbeing. Per your settings, we didn’t notify others in your family in Miya—lean on people you trust in real life; professional support is okay to ask for too.`,
        }
        : {
          title: `2 weeks: ${metric} off your pattern`,
          body:
            `Two weeks counts as a stretch. You’ve kept this private in Miya for now—small steps still matter, and you’re not failing anyone.`,
        };
    }
    return band === "marked"
      ? {
        title: `2 weeks: big ${metric} drop`,
        body:
          `A sustained big change is worth taking seriously—for your wellbeing. Your family on Miya has been kept in the loop; professional support is okay to ask for too.`,
      }
      : {
        title: `2 weeks: ${metric} off your pattern`,
        body:
          `Two weeks counts as a stretch. Others in your family on Miya can support you—small steps still matter, and you’re not failing anyone.`,
      };
  }
  if (sole) {
    return band === "marked"
      ? {
        title: `3 weeks: ${metric} needs extra care`,
        body:
          `Your wellbeing matters. Loop in your doctor if it feels right—you’re the only person in your family on Miya, so be gentle with yourself and reach out to people you trust outside the app.`,
      }
      : {
        title: `3 weeks: ${metric} not back to usual`,
        body:
          `Three weeks is a lot to carry alone. You’re the only one in your family on Miya—reach out to someone you trust in real life; no blame, just support.`,
      };
  }
  if (!notifiedFamilyInApp) {
    return band === "marked"
      ? {
        title: `3 weeks: ${metric} needs extra care`,
        body:
          `Your wellbeing matters. You asked us not to alert your family in Miya for this—loop in your doctor if it feels right, and reach out to people you trust outside the app.`,
      }
      : {
        title: `3 weeks: ${metric} not back to usual`,
        body:
          `Three weeks is a lot to carry alone. Others in your family weren’t notified in the app per your settings—reach out in real life when you’re ready; no blame, just support.`,
      };
  }
  return band === "marked"
    ? {
      title: `3 weeks: ${metric} needs extra care`,
      body:
        `Your wellbeing matters. Your family on Miya has been notified; loop in your doctor too if it feels right—we want you supported, not stressed.`,
    }
    : {
      title: `3 weeks: ${metric} not back to usual`,
      body:
        `Three weeks is a lot to carry alone. Everyone in your family on Miya can help make a simple, kind plan with you—no blame, just support.`,
    };
}

// Returns { title, body } for push-capable kinds, or null if we intentionally do not push this kind.
function buildAlert(
  payload: any,
  memberName: string,
): { title: string; body: string } | null {
  const kind: string = payload.kind ?? "";
  const pillar = formatPillar(payload.pillar ?? "");
  const success = payload.status === "completed_success";
  const daysEval = payload.days_evaluated ?? payload.days_succeeded;
  const remaining = payload.remaining_days ?? "";
  const needed = payload.successes_needed ?? "";

  switch (kind) {
    case "pattern_alert":
      return buildPatternAlertCopy(payload, memberName);

    case "challenge_invite":
      return {
        title: `You’re invited: ${pillar} challenge`,
        body: `No pressure—open Miya when you’re ready to peek or say yes. We’d love to have you.`,
      };

    case "challenge_completed_member":
      return {
        title: success ? `You finished the ${pillar} challenge` : `${pillar} challenge wrapped up`,
        body: success
          ? `That took effort—nice work. Open Miya to see what’s next, no rush.`
          : `The goal didn’t land this round, and that’s human. Another try is there whenever you want it.`,
      };

    case "challenge_completed_admin":
      return {
        title: success ? `${memberName} finished the ${pillar} challenge` : `${memberName}’s ${pillar} challenge ended`,
        body: success
          ? `Worth a little celebration—they showed up. Say something kind in Miya or in person.`
          : `The bar wasn’t met—no shame. A warm check-in beats silence.`,
      };

    case "challenge_invite_expired":
      return {
        title: `${pillar} challenge invite quietly closed`,
        body:
          `${memberName} didn’t jump in this time—that’s okay. A gentle real-life hello might feel better than another ping.`,
      };

    case "competitive_challenge_invite": {
      const focusLabel = formatCompetitiveFocus(payload.focus ?? "");
      const modeLabel = payload.mode === "family_brawl" ? "family brawl" : "head-to-head";
      return {
        title: `${memberName} called you out — ${focusLabel}`,
        body: `${modeLabel} this week. Highest ${focusLabel.toLowerCase()} wins. Open Miya to accept.`,
      };
    }

    case "competitive_challenge_invite_accepted": {
      const focusLabel = formatCompetitiveFocus(payload.focus ?? "");
      const pendingCount = Number(payload.pending_count ?? 0);
      return {
        title: `${memberName} is in`,
        body: pendingCount > 0
          ? `Just ${pendingCount} more ${pendingCount === 1 ? "person" : "people"} to go before the ${focusLabel.toLowerCase()} week kicks off.`
          : `Everyone’s ready. The challenge is starting.`,
      };
    }

    case "competitive_challenge_started": {
      const focusLabel = formatCompetitiveFocus(payload.focus ?? "");
      return {
        title: `Game on — ${focusLabel} challenge starts now`,
        body: `Mon–Sun. Best score wins. Open Miya to see the matchup.`,
      };
    }

    case "competitive_challenge_declined": {
      return {
        title: `${memberName} sat this one out`,
        body: `Challenge cancelled for everyone — no hard feelings. Start a fresh one whenever you’re ready.`,
      };
    }

    case "competitive_challenge_lead_change": {
      const focusLabel = formatCompetitiveFocus(payload.focus ?? "");
      const leaderName = (payload.leader_name as string | undefined) ?? memberName;
      const youAhead = !!payload.you_ahead;
      return youAhead
        ? {
            title: `You’re leading the ${focusLabel.toLowerCase()} challenge`,
            body: `Hold the lead through Sunday — open Miya to see by how much.`,
          }
        : {
            title: `${leaderName} just took the lead`,
            body: `Still anyone’s week. Open Miya to see the gap.`,
          };
    }

    case "competitive_challenge_final_push": {
      const focusLabel = formatCompetitiveFocus(payload.focus ?? "");
      return {
        title: `One day left — ${focusLabel} challenge`,
        body: `It’s close enough to flip. Open Miya for the final tally.`,
      };
    }

    case "competitive_challenge_result": {
      const focusLabel = formatCompetitiveFocus(payload.focus ?? "");
      const youWon = !!payload.you_won;
      const draw = payload.outcome === "draw";
      if (draw) {
        return {
          title: `Photo finish — ${focusLabel.toLowerCase()} challenge tied`,
          body: `Decide it with a tie-break or run it back. Open Miya to choose.`,
        };
      }
      return youWon
        ? {
            title: `You won the ${focusLabel.toLowerCase()} challenge`,
            body: `Champions points earned. Open Miya to see the breakdown.`,
          }
        : {
            title: `${memberName} took the ${focusLabel.toLowerCase()} challenge`,
            body: `Open Miya to see the final scores — and run it back if you want.`,
          };
    }

    case "challenge_daily_member": {
      const d = daysEval != null ? String(daysEval) : "?";
      return {
        title: `Day ${d} of 7 — ${pillar}`,
        body: `You’re doing fine. Open Miya for a small, friendly nudge whenever you like.`,
      };
    }

    case "challenge_daily_admin":
      return {
        title: `${memberName} — day ${daysEval ?? "?"} of 7, ${pillar}`,
        body: `On track so far. A short word of encouragement from you could mean a lot.`,
      };

    case "invite_joined": {
      const firstName = payload.member_first_name ?? memberName;
      return {
        title: `${firstName}’s here—welcome them`,
        body: `Their profile is live. Say hi when it feels natural; we’re glad they’re part of the family.`,
      };
    }

    case "care_outcome":
      return {
        title: `Lovely news about ${memberName}’s health signal`,
        body:
          payload.outcome_message ??
          `Closer to their baseline again—your care may have helped more than you know.`,
      };

    case "missing_wearable": {
      const days = Number(payload.days_stale ?? 3);
      const critical = days >= 7 || payload.severity === "critical";
      return critical
        ? {
          title: `${memberName} — we’d love fresh data when they’re ready`,
          body:
            `About a week without sync makes alerts harder. Offer to help them reconnect when it feels supportive.`,
        }
        : {
          title: `${memberName} — wearable’s gone quiet a few days`,
          body:
            `Maybe a dead battery or a busy week. A kind nudge to sync or charge could help—no lecture needed.`,
        };
    }

    case "billing_owner_left":
      return {
        title: `Let’s keep the family on Miya together`,
        body:
          `Someone lovely can take over billing within 7 days—tap when you’re ready; we’ll walk you through it.`,
      };

    case "billing_grace_reminder": {
      const rt = payload.reminder_type as string | undefined;
      const final = rt === "final_day" || (payload as any).reminder_type === "final_day";
      return final
        ? {
          title: `Last day to choose a new billing owner`,
          body: `One more window to keep everyone covered. You’ve got this—open Miya and we’ll help.`,
        }
        : {
          title: `A few days left to sort billing`,
          body:
            `No stress—whoever can step in, Miya’s here to make it simple for the whole family.`,
        };
    }

    case "billing_interrupted":
      return {
        title: `Miya’s paused for now—we’re still with you`,
        body:
          `Restore billing when someone’s ready; your family’s space will be waiting. No blame.`,
      };

    case "billing_restored":
      return {
        title: `You’re all set—welcome back`,
        body: `Family access is on again. Thanks for taking care of everyone.`,
      };

    case "personal_trend":
      return {
        title: `Movement shifted vs your usual`,
        body: `Just a friendly heads-up—open Miya for context, not a verdict. You’re doing okay.`,
      };

    default:
      return null;
  }
}

async function getMemberFirstName(memberUserId: string | undefined): Promise<string> {
  if (!memberUserId) return "Your family member";
  const { data } = await supabase
    .from("family_members")
    .select("first_name")
    .eq("user_id", memberUserId)
    .maybeSingle();
  return (data?.first_name as string | null) ?? "Your family member";
}

type PushAttempt = { outcome: "sent" | "skipped" | "failed"; error?: string };

// ── Send push notification via APNs ──────────────────────────────────────────
async function sendPushNotification(
  recipientUserId: string,
  payload: any,
): Promise<PushAttempt> {
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

  if (!bundleId || !keyId || !teamId || !privateKey) {
    console.log("⚠️ APNs secrets not configured — marking skipped (not sent)");
    return { outcome: "skipped", error: "apns_not_configured" };
  }

  // Resolve member name for notification copy
  const memberName = await getMemberFirstName(payload.member_user_id);

  const alert = buildAlert(payload, memberName);
  if (!alert) {
    console.log(`⏭️ No push template for kind: ${payload.kind ?? "unknown"}`);
    return { outcome: "skipped", error: "no_push_template" };
  }

  // Fetch active device tokens for this user
  const { data: tokens, error: tokenErr } = await supabase
    .from("device_tokens")
    .select("device_token")
    .eq("user_id", recipientUserId)
    .eq("platform", "ios")
    .eq("is_active", true);

  if (tokenErr) {
    console.error("Error fetching device tokens:", tokenErr);
    return { outcome: "failed", error: "token_fetch_error" };
  }

  if (!tokens?.length) {
    console.log("⚠️ No active device tokens for user:", recipientUserId);
    return { outcome: "failed", error: "no_device_tokens" };
  }

  const apnsBody = JSON.stringify({
    aps: {
      alert: { title: alert.title, body: alert.body },
      sound: "default",
      badge: 1,
    },
    data: payload,
  });

  let jwt: string;
  try {
    jwt = await getApnsJwt();
  } catch (e) {
    console.error("APNs JWT generation failed:", e);
    return { outcome: "failed", error: `jwt_error: ${e}` };
  }

  const useSandbox = Deno.env.get("APNS_USE_SANDBOX")?.toLowerCase() === "true";
  const apnsHost = useSandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";

  let anySuccess = false;

  for (const { device_token } of tokens) {
    try {
      const res = await fetch(
        `${apnsHost}/3/device/${device_token}`,
        {
          method: "POST",
          headers: {
            "authorization": `bearer ${jwt}`,
            "apns-topic": bundleId,
            "apns-push-type": "alert",
            "content-type": "application/json",
          },
          body: apnsBody,
        },
      );

      if (res.status === 200) {
        anySuccess = true;
        console.log(`✅ APNs push sent [${payload.kind}] to user:`, recipientUserId);
      } else if (res.status === 410) {
        // Token permanently invalid — deactivate so we don't waste future requests
        await supabase
          .from("device_tokens")
          .update({ is_active: false })
          .eq("device_token", device_token);
        console.log("🗑️ Deactivated expired APNs token for user:", recipientUserId);
      } else {
        const body = await res.json().catch(() => ({}));
        console.error("APNs error:", res.status, body);
      }
    } catch (e) {
      console.error("APNs fetch error:", e);
    }
  }

  return anySuccess
    ? { outcome: "sent" }
    : { outcome: "failed", error: "apns_delivery_failed" };
}

// Process a single notification
async function processNotification(notification: any): Promise<{
  success: boolean;
  error?: string;
  skipped?: boolean;
  reason?: string;
}> {
  const {
    id,
    recipient_user_id,
    alert_state_id,
    channel,
    payload,
    attempts,
  } = notification;

  console.log("🔔 Processing notification:", {
    id,
    recipient_user_id,
    channel,
    attempts,
  });

  // Get alert severity for quiet hours check
  let severity = "watch";
  if (alert_state_id) {
    const { data: alert } = await supabase
      .from("pattern_alert_state")
      .select("severity")
      .eq("id", alert_state_id)
      .maybeSingle();

    if (alert?.severity) {
      severity = alert.severity;
    }
  } else if (payload?.severity && typeof payload.severity === "string") {
    // Non-pattern notifications (e.g. missing_wearable, challenges) can pass severity in payload
    severity = payload.severity;
  }

  // Check if should send based on user preferences
  const { shouldSend, reason } = await shouldSendNotification(
    recipient_user_id,
    alert_state_id,
    severity,
  );

  if (!shouldSend) {
    console.log("⏭️ Skipping notification:", { id, reason });

    // Update notification to mark as skipped
    await supabase
      .from("notification_queue")
      .update({
        status: "skipped",
        last_error: reason || "skipped_by_preferences",
        updated_at: new Date().toISOString(),
      })
      .eq("id", id);

    return { success: true, skipped: true, reason };
  }

  let pushResult: PushAttempt | null = null;

  switch (channel) {
    case "push":
      pushResult = await sendPushNotification(recipient_user_id, payload);
      break;

    case "whatsapp":
      console.log("📱 WhatsApp notification (not implemented):", {
        recipient_user_id,
        payload,
      });
      pushResult = { outcome: "failed", error: "whatsapp_not_implemented" };
      break;

    case "sms":
      console.log("📱 SMS notification (not implemented):", {
        recipient_user_id,
        payload,
      });
      pushResult = { outcome: "failed", error: "sms_not_implemented" };
      break;

    case "email":
      console.log("📧 Email notification (not implemented):", {
        recipient_user_id,
        payload,
      });
      pushResult = { outcome: "failed", error: "email_not_implemented" };
      break;

    default:
      pushResult = { outcome: "failed", error: "unknown_channel" };
  }

  if (!pushResult) {
    return { success: false, error: "internal_no_channel_result" };
  }

  if (pushResult.outcome === "skipped") {
    await supabase
      .from("notification_queue")
      .update({
        status: "skipped",
        last_error: pushResult.error || "push_skipped",
        updated_at: new Date().toISOString(),
      })
      .eq("id", id);
    console.log("⏭️ Push skipped (not sent):", id, pushResult.error);
    return { success: true, skipped: true, reason: pushResult.error };
  }

  if (pushResult.outcome === "sent") {
    await supabase
      .from("notification_queue")
      .update({
        status: "sent",
        sent_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq("id", id);
    console.log("✅ Notification sent successfully:", id);
    return { success: true };
  }

  const newAttempts = (attempts || 0) + 1;
  const maxAttempts = 5;
  await supabase
    .from("notification_queue")
    .update({
      status: newAttempts >= maxAttempts ? "failed" : "pending",
      attempts: newAttempts,
      last_error: pushResult.error || "unknown_error",
      updated_at: new Date().toISOString(),
    })
    .eq("id", id);

  console.log("❌ Notification failed:", { id, error: pushResult.error, attempts: newAttempts });
  return { success: false, error: pushResult.error };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  if (req.method === "GET") {
    return jsonResponse({ ok: true, message: "process_notifications worker alive" });
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

  try {
    // Query pending notifications (limit to batch size)
    let body: any = {};
    try {
      body = await req.json();
    } catch {
      body = {};
    }

    const batchSize = body.batchSize || 50;
    const maxAge = body.maxAge ?? 72; // hours — wider default so brief worker outages don’t strand rows

    const { data: notifications, error } = await supabase
      .from("notification_queue")
      .select("*")
      .eq("status", "pending")
      .lt("attempts", 5)
      .gte(
        "created_at",
        new Date(Date.now() - maxAge * 60 * 60 * 1000).toISOString(),
      )
      .order("created_at", { ascending: true })
      .limit(batchSize);

    if (error) {
      console.error("Error fetching notifications:", error);
      return jsonResponse({ ok: false, error: error.message }, 500);
    }

    if (!notifications || notifications.length === 0) {
      return jsonResponse({
        ok: true,
        message: "No pending notifications",
        processed: 0,
      });
    }

    console.log(`📬 Found ${notifications.length} pending notifications`);

    // Process each notification
    const results = [];
    for (const notification of notifications) {
      const result = await processNotification(notification);
      results.push({
        id: notification.id,
        ...result,
      });
    }

    const sent = results.filter((r) => r.success && !r.skipped).length;
    const skipped = results.filter((r) => r.skipped).length;
    const failed = results.filter((r) => !r.success).length;

    return jsonResponse({
      ok: true,
      processed: notifications.length,
      sent,
      skipped,
      failed,
      results,
    });
  } catch (error) {
    console.error("Error processing notifications:", error);
    return jsonResponse(
      {
        ok: false,
        error: error instanceof Error ? error.message : "Unknown error",
      },
      500,
    );
  }
});
