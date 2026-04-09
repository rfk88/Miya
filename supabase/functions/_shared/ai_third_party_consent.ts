import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Returns true only when privacy_settings explicitly allows third-party AI for this user.
 * No row, NULL column, or fetch error => false (fail closed for OpenAI calls).
 */
export async function isAIThirdPartySharingEnabledForUser(
  admin: SupabaseClient,
  userId: string,
): Promise<boolean> {
  if (!userId) return false;
  const { data, error } = await admin
    .from("privacy_settings")
    .select("ai_third_party_sharing_enabled")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    console.warn("ai_third_party_consent: privacy_settings read failed", error.message);
    return false;
  }
  if (!data) return false;
  return data.ai_third_party_sharing_enabled === true;
}

/** Body for HTTP 403 when OpenAI must not run (align keys with miya_insight family). */
export const AI_CONSENT_DENIED_JSON = {
  ok: false,
  error: "ai_consent_required",
  message: "Third-party AI features are off for this account. Enable them in Settings.",
} as const;
