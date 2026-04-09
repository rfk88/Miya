import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AI_CONSENT_DENIED_JSON,
  isAIThirdPartySharingEnabledForUser,
} from "../_shared/ai_third_party_consent.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const TONE_INSTRUCTIONS: Record<string, string> = {
  "Warm & caring":
    "Warm and compassionate. Sound like a caring friend or family member. Lead with empathy, use gentle language, avoid pressure.",
  Motivating:
    "Encouraging and upbeat without being pushy. Celebrate effort and possibility. No guilt, no shame.",
  "Direct & friendly":
    "Clear and concise, still kind. Short sentences. No coldness, no blame.",
};

const BASE_FAMILY_SAFE_RULES = `
Family-safe rules (always):
- Never shame, blame, or mock anyone for their health.
- Do not add new medical claims, numbers, dates, or diagnoses that were not in the original.
- Do not remove or alter specific facts that were in the original (names, numbers, dates, scores).
- Keep the same core intent: you're still sending the same message, just rephrased.
- Plain, natural English suitable for SMS or WhatsApp.
- Output ONLY the rewritten message text — no quotes, no preamble, no labels.`.trim();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Use POST" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !anonKey) {
      throw new Error("Missing Supabase config");
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceRoleKey) {
      return jsonResponse({ error: "Server misconfigured" }, 500);
    }
    const admin = createClient(supabaseUrl, serviceRoleKey);
    const regenConsentOk = await isAIThirdPartySharingEnabledForUser(admin, userData.user.id);
    if (!regenConsentOk) {
      return jsonResponse({ ...AI_CONSENT_DENIED_JSON }, 403);
    }

    const body = await req.json().catch(() => null);
    const original_message = body?.original_message;
    const tone = body?.tone;
    const member_name = body?.member_name;

    if (original_message == null || tone == null) {
      return jsonResponse({ error: "Missing required fields" }, 400);
    }

    if (typeof tone !== "string") {
      return jsonResponse({ error: "tone must be a string" }, 400);
    }

    const ALLOWED_TONES = new Set(Object.keys(TONE_INSTRUCTIONS));
    const toneTrimmed = String(tone).trim();
    if (!ALLOWED_TONES.has(toneTrimmed)) {
      console.warn("regenerate_message: invalid tone", tone);
      return jsonResponse(
        {
          error: "Invalid tone. Allowed values: Warm & caring, Motivating, Direct & friendly",
        },
        400,
      );
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      throw new Error("OpenAI API key not configured");
    }

    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";
    const toneHint = TONE_INSTRUCTIONS[toneTrimmed];
    const aboutName =
      member_name && String(member_name).trim()
        ? `The message is about: ${String(member_name).trim()}.`
        : "Keep the message personal and kind.";

    const systemContent = [
      "You rewrite short wellness outreach messages for families.",
      BASE_FAMILY_SAFE_RULES,
      "",
      `Tone target: ${toneTrimmed}.`,
      toneHint,
    ].join("\n");

    const userContent = `Rewrite the following message in the "${toneTrimmed}" tone.

${aboutName}

Original message (preserve meaning and all factual details):
"""
${String(original_message)}
"""

Return only the rewritten message text, similar length.`;

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: systemContent },
          { role: "user", content: userContent },
        ],
        temperature: 0.65,
        max_tokens: 320,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error("regenerate_message: OpenAI error", response.status, errorText);
      throw new Error(`OpenAI error: ${response.status}`);
    }

    const data = await response.json();
    const message = data.choices?.[0]?.message?.content?.trim();

    if (!message) {
      throw new Error("No message generated");
    }

    return jsonResponse({ message });
  } catch (error) {
    console.error("regenerate_message:", error);
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Internal error" },
      500,
    );
  }
});
