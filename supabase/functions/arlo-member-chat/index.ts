import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  AI_CONSENT_DENIED_JSON,
  isAIThirdPartySharingEnabledForUser,
} from "../_shared/ai_third_party_consent.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const FALLBACK_TIMEOUT =
  "Sorry — that took a bit too long. When you're ready, tell me what you'd most like to focus on for this person — sleep, movement, recovery, or the big picture.";
const FALLBACK_NETWORK =
  "Sorry — I couldn't reach Miya just now. Please try again in a moment.";
const FALLBACK_OPENAI_PREFIX = "I couldn't finish that reply just now.";
const FALLBACK_UNHANDLED =
  "Sorry — something went wrong on my side. Please try again, or ask about sleep, movement, or recovery.";

const EMERGENCY_REPLY =
  "If you or someone with you might be having a medical emergency — for example severe chest pain, trouble breathing, confusion, weakness on one side, severe bleeding, or thoughts of self-harm — please contact emergency services straight away (999 in the UK, 911 in the US) or go to A&E. I'm not able to help with emergencies here. Once everyone is safe, I'm here for everyday wellbeing questions.";

type ChatMessage = {
  role: "system" | "user" | "assistant";
  content: string;
};

type MemberFacts = {
  memberId: string;
  memberName: string;
  vitalityScore?: number;
  vitalityDeltaPercent?: number;
  sleepValue?: string | null;
  sleepChangeText?: string | null;
  movementValue?: string | null;
  movementChangeText?: string | null;
  recoveryValue?: string | null;
  recoveryChangeText?: string | null;
};

function safeJsonHeaders(extra: Record<string, string> = {}) {
  return { ...corsHeaders, "Content-Type": "application/json", ...extra };
}

function looksLikeUrgentMedicalOrCrisis(userTexts: string[]): boolean {
  const combined = userTexts.join(" ").toLowerCase();
  if (combined.length < 3) return false;
  const patterns: RegExp[] = [
    /\b999\b|\b911\b|\bemergency\b|\ba&e\b|\ber\b|\bambulance\b/,
    /\bchest pain\b|\bheart attack\b|\bcrushing (chest|pain)\b/,
    /\b(can't|cannot) breathe\b|\btrouble breathing\b|\bchoking\b|\bgasping\b/,
    /\bstroke\b|\bfacial droop\b|\bone side (of my|of the) (face|body)\b|\bslurred speech\b/,
    /\bsuicid\w*\b|\bkill myself\b|\bend my life\b|\bwant to die\b/,
    /\bself[- ]harm\b|\bcut myself\b/,
    /\bunconscious\b|\bpassed out\b|\bnon[- ]responsive\b/,
    /\bsevere bleed\w*\b|\buncontrolled bleed\w*\b/,
  ];
  return patterns.some((p) => p.test(combined));
}

function getIntentGuide(intent: string): string {
  switch (intent) {
    case "member_doing_well":
      return "Celebrate genuine strengths. Tie praise to specific signals in the member facts. Avoid empty cheer — say why it matters for their week.";
    case "member_needs_support":
      return "Lead with empathy (no blame). Name what looks harder from the data, then one gentle, realistic action. Offer hope without minimising.";
    case "member_sleep":
    case "member_sleep_improve":
      return "Focus on sleep only. Ground advice in sleep-related lines from the facts; if sleep data is missing, say so and give general sleep-hygiene ideas without pretending you saw their charts.";
    case "member_movement":
    case "member_move":
      return "Focus on movement/activity only. Use movement lines from the facts; suggest small, achievable steps.";
    case "member_recovery":
    case "member_rec":
      return "Focus on recovery only. Use recovery-related lines from the facts; avoid medical diagnosis; encourage sustainable habits.";
    case "member_overview":
      return "Give a balanced snapshot: what's steady, what might need attention, and one priority — all grounded in the facts provided.";
    default:
      return "Answer the user's question directly. Ground every claim in the member facts when present; otherwise state clearly what you cannot see.";
  }
}

function hasUsefulFacts(facts: MemberFacts | null): boolean {
  if (!facts) return false;
  return (
    facts.vitalityScore !== undefined ||
    !!facts.sleepValue ||
    !!facts.movementValue ||
    !!facts.recoveryValue
  );
}

function buildMemberSystemPrompt(opts: {
  identityContext: string;
  intentGuide: string;
  memberName: string;
  factsPresent: boolean;
}): string {
  const { identityContext, intentGuide, memberName, factsPresent } = opts;
  const dataLine = factsPresent
    ? `Member facts are provided in a separate system message — treat them as the only numeric/descriptive data you may cite for ${memberName}.`
    : `Limited or no structured member facts are available — say so in one short sentence and do not invent scores, trends, or wearable details. Offer general, kind guidance only.`;

  return `
You are Miya: a warm, trustworthy wellbeing coach for families (British English).

${identityContext}

${intentGuide ? `FOCUS FOR THIS TURN:\n${intentGuide}\n` : ""}

TRUST CONTRACT:
1) If the user sounds worried, acknowledge that first (one sentence). Never shame or blame.
2) ${dataLine}
3) Do not diagnose medical conditions, prescribe medication, or claim certainty from wearables.
4) Prefer plain language. When you reference data, quote the facts message in everyday words (e.g. "recovery looks softer this week") not clinical jargon unless the facts use it.
5) Give one realistic next step for the next 24 hours when advice fits — small and kind.
6) Optional: end with at most ONE short follow-up question if it genuinely helps — as the last sentence. If no question is needed, end with a supportive closing line instead.
7) Do not repeat your previous answer verbatim; build on the thread.

SAFETY: If emergency symptoms may be present, do not coach — direct to urgent care. (The system may intercept these messages.)

LENGTH: Roughly 50–150 words depending on complexity. Sound human, not templated.
`.trim();
}

/**
 * Generate contextual follow-up pills based on what Miya JUST said
 */
function generateResponseAwarePills(
  memberName: string,
  aiResponse: string,
  currentIntent: string,
  facts: MemberFacts | null,
  messages: ChatMessage[],
): Array<{ id: string; title: string; intent: string }> {
  const pills: Array<{ id: string; title: string; intent: string }> = [];

  const responseLower = aiResponse.toLowerCase();
  const mentionedSleep = responseLower.includes("sleep");
  const mentionedMovement =
    responseLower.includes("movement") || responseLower.includes("activity") || responseLower.includes("steps");
  const mentionedRecovery =
    responseLower.includes("recovery") || responseLower.includes("hrv") || responseLower.includes("heart rate");

  const hasPositiveTrend = responseLower.match(
    /\b(strong|up|improved|above|good|well|increase|higher|better)\b/,
  );
  const hasNegativeTrend = responseLower.match(
    /\b(down|dropped|below|low|declining|decrease|lower|worse)\b/,
  );

  const userMessageCount = messages.filter((m) => m.role === "user").length;

  if (mentionedRecovery && facts?.recoveryValue) {
    if (hasPositiveTrend) {
      pills.push({ id: "recovery_maintain", title: "How to keep this going?", intent: "member_recovery" });
      pills.push({ id: "recovery_driver", title: "What's driving this?", intent: "member_recovery" });
    } else {
      pills.push({ id: "recovery_improve", title: "How to improve recovery?", intent: "member_recovery" });
    }
  }

  if (mentionedSleep && facts?.sleepValue) {
    if (hasPositiveTrend) {
      pills.push({ id: "sleep_maintain", title: "Set a gentle sleep goal", intent: "member_sleep" });
    } else {
      pills.push({ id: "sleep_improve", title: "How to improve sleep?", intent: "member_sleep" });
    }
  }

  if (mentionedMovement && facts?.movementValue) {
    if (hasPositiveTrend) {
      pills.push({ id: "movement_goal", title: "What's a realistic goal?", intent: "member_movement" });
    } else {
      pills.push({ id: "movement_increase", title: "How to move a bit more?", intent: "member_movement" });
    }
  }

  if (hasPositiveTrend && currentIntent === "member_doing_well") {
    if (!mentionedSleep && facts?.sleepValue) {
      pills.push({ id: "explore_sleep", title: "Check sleep patterns", intent: "member_sleep" });
    }
    if (!mentionedMovement && facts?.movementValue) {
      pills.push({ id: "explore_movement", title: "Check activity levels", intent: "member_movement" });
    }
    if (!mentionedRecovery && facts?.recoveryValue) {
      pills.push({ id: "explore_recovery", title: "Check recovery trends", intent: "member_recovery" });
    }
  }

  if (hasNegativeTrend || currentIntent === "member_needs_support") {
    pills.push({ id: "action", title: "What should we try first?", intent: "member_needs_support" });
    pills.push({ id: "priority", title: "What's most important?", intent: "member_needs_support" });
  }

  if (userMessageCount >= 2) {
    pills.push({
      id: "overview",
      title: `${memberName}'s overall picture`,
      intent: "member_overview",
    });
  }

  if (pills.length < 3) {
    if (currentIntent !== "member_doing_well") {
      pills.push({
        id: "well_fallback",
        title: `What's ${memberName} doing well?`,
        intent: "member_doing_well",
      });
    }
    if (currentIntent !== "member_needs_support") {
      pills.push({
        id: "support_fallback",
        title: "Where could we support them?",
        intent: "member_needs_support",
      });
    }
  }

  const uniquePills = Array.from(new Map(pills.map((p) => [p.id, p])).values());
  return uniquePills.slice(0, 4);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Use POST" }), {
      status: 405,
      headers: safeJsonHeaders(),
    });
  }

  const t0 = Date.now();
  console.log("arlo-member-chat: start");

  try {
    const body = await req.json().catch(() => null);

    const messages = (body?.messages ?? []) as ChatMessage[];
    const memberName = String(body?.member_name ?? "this person");
    const intent = String(body?.intent ?? "");
    const facts = body?.facts as MemberFacts | null;

    if (!Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: "Missing messages array." }), {
        status: 400,
        headers: safeJsonHeaders(),
      });
    }

    const recentUserTexts = messages
      .filter((m) => m.role === "user")
      .map((m) => m.content)
      .slice(-5);
    if (looksLikeUrgentMedicalOrCrisis(recentUserTexts)) {
      console.log("arlo-member-chat: urgent/crisis pattern — skipping model");
      return new Response(
        JSON.stringify({
          reply: EMERGENCY_REPLY,
          suggested_prompts: [],
        }),
        { status: 200, headers: safeJsonHeaders() },
      );
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";

    if (!apiKey) {
      return new Response(JSON.stringify({ error: "Missing OPENAI_API_KEY secret." }), {
        status: 500,
        headers: safeJsonHeaders(),
      });
    }

    const authHeader = req.headers.get("authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";

    let callerId: string | null = null;
    if (jwt) {
      try {
        const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
        if (supabaseUrl && anonKey) {
          const supabase = createClient(supabaseUrl, anonKey);
          const { data: userData } = await supabase.auth.getUser(jwt);
          callerId = userData?.user?.id ?? null;
        }
      } catch (e) {
        console.log("arlo-member-chat: Could not extract viewer ID", String(e));
      }
    }

    const memberId = String(body?.member_id ?? "");
    const isViewingSelf = !!(callerId && memberId && callerId === memberId);

    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const dataSubjectId = memberId || callerId;
    if (supabaseUrl && serviceRoleKey && dataSubjectId) {
      const admin = createClient(supabaseUrl, serviceRoleKey);
      const allowed = await isAIThirdPartySharingEnabledForUser(admin, dataSubjectId);
      if (!allowed) {
        console.log("arlo-member-chat: third-party AI consent denied for", dataSubjectId);
        return new Response(JSON.stringify(AI_CONSENT_DENIED_JSON), {
          status: 403,
          headers: safeJsonHeaders(),
        });
      }
    } else {
      console.log("arlo-member-chat: missing service role or subject id — refusing OpenAI");
      return new Response(JSON.stringify({ error: "Server misconfigured" }), {
        status: 500,
        headers: safeJsonHeaders(),
      });
    }

    const identityContext = isViewingSelf
      ? "The viewer is asking about their own data. Use \"you\" and \"your\" naturally. Be kind and non-judgmental."
      : `The viewer cares about ${memberName}. Use their name when it helps clarity. Sound supportive — like you're helping someone check in on a loved one without blame.`;

    const intentGuide = getIntentGuide(intent);
    const factsPresent = hasUsefulFacts(facts);

    const system: ChatMessage = {
      role: "system",
      content: buildMemberSystemPrompt({
        identityContext,
        intentGuide,
        memberName,
        factsPresent,
      }),
    };

    console.log(`arlo-member-chat: isViewingSelf=${isViewingSelf} (callerId=${callerId}, memberId=${memberId})`);

    const factsLines: string[] = [];
    if (facts) {
      factsLines.push(`Member facts for ${facts.memberName} (ground truth for this reply):`);

      if (facts.vitalityScore !== undefined) {
        const delta = facts.vitalityDeltaPercent
          ? ` (${facts.vitalityDeltaPercent > 0 ? "+" : ""}${facts.vitalityDeltaPercent}%)`
          : "";
        factsLines.push(`Vitality: ${facts.vitalityScore}${delta}`);
      }

      if (facts.sleepValue) {
        factsLines.push(`Sleep: ${facts.sleepValue}${facts.sleepChangeText ? ` — ${facts.sleepChangeText}` : ""}`);
      }

      if (facts.movementValue) {
        factsLines.push(
          `Movement: ${facts.movementValue}${facts.movementChangeText ? ` — ${facts.movementChangeText}` : ""}`,
        );
      }

      if (facts.recoveryValue) {
        factsLines.push(
          `Recovery: ${facts.recoveryValue}${facts.recoveryChangeText ? ` — ${facts.recoveryChangeText}` : ""}`,
        );
      }
    }

    const factsMessage: ChatMessage | null =
      factsLines.length > 1
        ? { role: "system", content: factsLines.join("\n") }
        : {
            role: "system",
            content:
              "No detailed member metrics were provided in this request — acknowledge the limit briefly; do not invent wearable or health data.",
          };

    const recentMessages = messages
      .filter((m) => typeof m.content === "string" && m.content.trim().length > 0)
      .slice(-10);

    const input: ChatMessage[] = [system, factsMessage, ...recentMessages];

    console.log("arlo-member-chat: calling openai", { model, inputCount: input.length, member: memberName });

    const controller = new AbortController();
    const timeoutMs = 45000;
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    let resp: Response;
    try {
      resp = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model,
          messages: input,
          max_tokens: 320,
        }),
        signal: controller.signal,
      });
    } catch (err) {
      const msg = String(err);
      const isAbort = msg.toLowerCase().includes("abort");

      console.log("arlo-member-chat: openai fetch threw", msg);

      return new Response(
        JSON.stringify({
          reply: isAbort ? FALLBACK_TIMEOUT : FALLBACK_NETWORK,
          suggested_prompts: [],
        }),
        { status: 200, headers: safeJsonHeaders() },
      );
    } finally {
      clearTimeout(timeout);
    }

    console.log("arlo-member-chat: openai returned", resp.status, "ms", Date.now() - t0);

    let data: any = null;
    try {
      data = await resp.json();
    } catch {
      const t = await resp.text().catch(() => "");
      data = { parse_error: true, status: resp.status, body: t };
    }

    if (!resp.ok) {
      console.log("arlo-member-chat: openai not ok", { status: resp.status, data });

      return new Response(
        JSON.stringify({
          reply: `${FALLBACK_OPENAI_PREFIX} What aspect of ${memberName}'s wellbeing would you like to explore next?`,
          status: resp.status,
          suggested_prompts: [],
        }),
        { status: 200, headers: safeJsonHeaders() },
      );
    }

    const reply =
      (data?.choices?.[0]?.message?.content?.trim()) ||
      `${FALLBACK_OPENAI_PREFIX} Please try again.`;

    const suggestedPrompts = generateResponseAwarePills(memberName, reply, intent, facts, recentMessages);

    console.log("arlo-member-chat: done, ms", Date.now() - t0, "pills", suggestedPrompts.length);

    return new Response(
      JSON.stringify({
        reply,
        suggested_prompts: suggestedPrompts,
      }),
      { status: 200, headers: safeJsonHeaders() },
    );
  } catch (e) {
    console.log("arlo-member-chat: unhandled error", String(e));

    return new Response(
      JSON.stringify({
        reply: FALLBACK_UNHANDLED,
        suggested_prompts: [],
        error: "Unhandled error",
      }),
      { status: 200, headers: safeJsonHeaders() },
    );
  }
});
