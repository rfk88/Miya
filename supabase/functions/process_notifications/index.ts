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

    // Check if alert is snoozed
    if (alertStateId) {
      const { data: alert, error: alertErr } = await supabase
        .from("pattern_alert_state")
        .select("snooze_until, dismissed_at")
        .eq("id", alertStateId)
        .maybeSingle();

      if (alertErr) {
        console.error("Error fetching alert state:", alertErr);
      } else if (alert) {
        if (alert.dismissed_at) {
          return { shouldSend: false, reason: "alert_dismissed" };
        }

        if (alert.snooze_until) {
          const snoozeUntil = new Date(alert.snooze_until);
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

// Send push notification (placeholder - integrate with APNs/FCM)
async function sendPushNotification(
  recipientUserId: string,
  payload: any,
): Promise<{ success: boolean; error?: string }> {
  // TODO: Integrate with APNs (Apple Push Notification service)
  // For now, log the notification
  console.log("📱 PUSH_NOTIFICATION:", {
    recipientUserId,
    payload,
  });

  // Placeholder: In production, this would:
  // 1. Fetch device tokens from device_tokens table
  // 2. Format APNs payload
  // 3. Send to Apple's APNs endpoint
  // 4. Handle response and update delivery status

  // For now, simulate success
  return { success: true };
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

  // Verify admin secret for security
  const expected = Deno.env.get("MIYA_ADMIN_SECRET") ?? "";
  const provided = req.headers.get("x-miya-admin-secret") ?? "";
  if (!expected || provided !== expected) {
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
