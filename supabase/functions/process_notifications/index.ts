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

// ── Notification content builder ─────────────────────────────────────────────
// Only these three kinds trigger a push. All others are silently skipped.

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

// Returns { title, body } for allowed notification kinds, or null to skip.
function buildAlert(
  payload: any,
  memberName: string,
): { title: string; body: string } | null {
  const kind: string = payload.kind ?? "";
  const pillar = formatPillar(payload.pillar ?? "");
  const metric = formatMetric(payload.metric_type ?? "");
  const days: number = payload.level ?? 3;
  const success = payload.status === "completed_success";

  switch (kind) {
    case "pattern_alert": {
      const direction = payload.pattern_type === "rise_vs_baseline" ? "elevated" : "lower than usual";
      return {
        title: `${memberName}'s health alert`,
        body: `${memberName}'s ${metric} has been ${direction} for ${days}+ days.`,
      };
    }

    case "challenge_invite":
      return {
        title: "New Health Challenge",
        body: `You've been invited to a ${pillar} challenge. Tap to see the details.`,
      };

    case "challenge_completed_member":
      return {
        title: success ? "Challenge Complete! 🎉" : "Challenge Ended",
        body: success
          ? `You completed your ${pillar} challenge. Great work!`
          : `Your ${pillar} challenge has ended.`,
      };

    case "challenge_completed_admin":
      return {
        title: success
          ? `${memberName} completed their challenge! 🎉`
          : `${memberName}'s challenge ended`,
        body: success
          ? `${memberName} finished the ${pillar} challenge successfully.`
          : `${memberName}'s ${pillar} challenge has ended.`,
      };

    default:
      return null; // Skip — not a notification kind we want to push
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

// ── Send push notification via APNs ──────────────────────────────────────────
async function sendPushNotification(
  recipientUserId: string,
  payload: any,
): Promise<{ success: boolean; error?: string }> {
  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

  if (!bundleId || !keyId || !teamId || !privateKey) {
    console.log("⚠️ APNs secrets not configured — skipping push");
    return { success: true }; // Degrade gracefully so queue doesn't get stuck
  }

  // Resolve member name for notification copy
  const memberName = await getMemberFirstName(payload.member_user_id);

  // Build the alert — returns null if this notification kind should not be pushed
  const alert = buildAlert(payload, memberName);
  if (!alert) {
    console.log(`⏭️ Skipping push for kind: ${payload.kind ?? "unknown"}`);
    return { success: true }; // Mark as handled so queue doesn't retry
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
    return { success: false, error: "token_fetch_error" };
  }

  if (!tokens?.length) {
    console.log("⚠️ No active device tokens for user:", recipientUserId);
    return { success: false, error: "no_device_tokens" };
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
    return { success: false, error: `jwt_error: ${e}` };
  }

  let anySuccess = false;

  for (const { device_token } of tokens) {
    try {
      const res = await fetch(
        `https://api.push.apple.com/3/device/${device_token}`,
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
    ? { success: true }
    : { success: false, error: "apns_delivery_failed" };
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

  // Send based on channel
  let result: { success: boolean; error?: string };

  switch (channel) {
    case "push":
      result = await sendPushNotification(recipient_user_id, payload);
      break;

    case "whatsapp":
      // TODO: Implement WhatsApp Business API integration
      console.log("📱 WhatsApp notification (not implemented):", {
        recipient_user_id,
        payload,
      });
      result = { success: false, error: "whatsapp_not_implemented" };
      break;

    case "sms":
      // TODO: Implement SMS via Twilio/AWS SNS
      console.log("📱 SMS notification (not implemented):", {
        recipient_user_id,
        payload,
      });
      result = { success: false, error: "sms_not_implemented" };
      break;

    case "email":
      // TODO: Implement email via SendGrid/AWS SES
      console.log("📧 Email notification (not implemented):", {
        recipient_user_id,
        payload,
      });
      result = { success: false, error: "email_not_implemented" };
      break;

    default:
      result = { success: false, error: "unknown_channel" };
  }

  // Update notification status
  if (result.success) {
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
  } else {
    const newAttempts = (attempts || 0) + 1;
    const maxAttempts = 5;

    await supabase
      .from("notification_queue")
      .update({
        status: newAttempts >= maxAttempts ? "failed" : "pending",
        attempts: newAttempts,
        last_error: result.error || "unknown_error",
        updated_at: new Date().toISOString(),
      })
      .eq("id", id);

    console.log("❌ Notification failed:", { id, error: result.error, attempts: newAttempts });
    return { success: false, error: result.error };
  }
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
    const maxAge = body.maxAge || 24; // hours

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
