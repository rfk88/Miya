import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

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

/**
 * Get intent-specific guidance for AI system prompt
 */
function getIntentGuide(intent: string): string {
  switch (intent) {
    case "member_doing_well":
      return "Focus on: Positive trends, strengths, what's working well. Celebrate wins with specific data points.";
    case "member_needs_support":
      return "Focus on: Areas for improvement, challenges, actionable support suggestions. Be constructive.";
    case "member_sleep":
    case "member_sleep_improve":
      return "Deep dive into sleep quality, duration, consistency. Use specific data points and actionable tips.";
    case "member_movement":
    case "member_move":
      return "Deep dive into activity levels, steps, exercise patterns. Use specific data and movement suggestions.";
    case "member_recovery":
    case "member_rec":
      return "Deep dive into recovery metrics (HRV, resting HR). Use specific data and recovery strategies.";
    default:
      return "";
  }
}

/**
 * Generate contextual follow-up pills based on what Miya JUST said
 */
function generateResponseAwarePills(
  memberName: string,
  aiResponse: string,
  currentIntent: string,
  facts: MemberFacts | null,
  messages: ChatMessage[]
): Array<{ id: string; title: string; intent: string }> {
  const pills: Array<{ id: string; title: string; intent: string }> = [];
  
  // Extract what metrics were mentioned in Miya's response
  const responseLower = aiResponse.toLowerCase();
  const mentionedSleep = responseLower.includes("sleep");
  const mentionedMovement = responseLower.includes("movement") || responseLower.includes("activity") || responseLower.includes("steps");
  const mentionedRecovery = responseLower.includes("recovery") || responseLower.includes("hrv") || responseLower.includes("heart rate");
  const mentionedVitality = responseLower.includes("vitality");
  
  // Extract if response indicated something positive or negative
  const hasPositiveTrend = responseLower.match(/\b(strong|up|improved|above|good|well|increase|higher|better)\b/);
  const hasNegativeTrend = responseLower.match(/\b(down|dropped|below|low|declining|decrease|lower|worse)\b/);
  
  // Track conversation depth
  const userMessageCount = messages.filter(m => m.role === "user").length;
  
  // Generate contextual follow-ups based on what was JUST discussed
  
  // If Miya mentioned recovery positively, offer to dig deeper or maintain
  if (mentionedRecovery && facts?.recoveryValue) {
    if (hasPositiveTrend) {
      pills.push({
        id: "recovery_maintain",
        title: "How to keep this going?",
        intent: "member_recovery"
      });
      pills.push({
        id: "recovery_driver",
        title: "What's driving this?",
        intent: "member_recovery"
      });
    } else {
      pills.push({
        id: "recovery_improve",
        title: "How to improve recovery?",
        intent: "member_recovery"
      });
    }
  }
  
  // If Miya mentioned sleep, offer sleep-specific follow-ups
  if (mentionedSleep && facts?.sleepValue) {
    if (hasPositiveTrend) {
      pills.push({
        id: "sleep_maintain",
        title: "Set a sleep goal",
        intent: "member_sleep"
      });
    } else {
      pills.push({
        id: "sleep_improve",
        title: "How to improve sleep?",
        intent: "member_sleep"
      });
    }
  }
  
  // If Miya mentioned movement, offer activity follow-ups
  if (mentionedMovement && facts?.movementValue) {
    if (hasPositiveTrend) {
      pills.push({
        id: "movement_goal",
        title: "What's a good goal?",
        intent: "member_movement"
      });
    } else {
      pills.push({
        id: "movement_increase",
        title: "How to move more?",
        intent: "member_movement"
      });
    }
  }
  
  // If discussing positives, offer to explore other areas or maintenance
  if (hasPositiveTrend && currentIntent === "member_doing_well") {
    // Suggest exploring other pillars not mentioned in response
    if (!mentionedSleep && facts?.sleepValue) {
      pills.push({
        id: "explore_sleep",
        title: "Check sleep patterns",
        intent: "member_sleep"
      });
    }
    if (!mentionedMovement && facts?.movementValue) {
      pills.push({
        id: "explore_movement",
        title: "Check activity levels",
        intent: "member_movement"
      });
    }
    if (!mentionedRecovery && facts?.recoveryValue) {
      pills.push({
        id: "explore_recovery",
        title: "Check recovery trends",
        intent: "member_recovery"
      });
    }
  }
  
  // If discussing concerns, offer action-oriented pills
  if (hasNegativeTrend || currentIntent === "member_needs_support") {
    pills.push({
      id: "action",
      title: "What should we do?",
      intent: "member_needs_support"
    });
    
    pills.push({
      id: "priority",
      title: "What's most important?",
      intent: "member_needs_support"
    });
  }
  
  // After a few exchanges, always offer a big picture view
  if (userMessageCount >= 2) {
    pills.push({
      id: "overview",
      title: `${memberName}'s overall health`,
      intent: "member_overview"
    });
  }
  
  // If we don't have enough pills yet, add complementary questions
  if (pills.length < 3) {
    if (currentIntent !== "member_doing_well") {
      pills.push({
        id: "well_fallback",
        title: `What's ${memberName} doing well?`,
        intent: "member_doing_well"
      });
    }
    if (currentIntent !== "member_needs_support") {
      pills.push({
        id: "support_fallback",
        title: `Where to focus next?`,
        intent: "member_needs_support"
      });
    }
  }
  
  // Ensure we have 3-4 unique pills
  const uniquePills = Array.from(new Map(pills.map(p => [p.id, p])).values());
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
    const memberName = String(body?.member_name ?? "");
    const intent = String(body?.intent ?? "");
    const facts = body?.facts as MemberFacts | null;

    if (!Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: "Missing `messages` array." }), {
        status: 400,
        headers: safeJsonHeaders(),
      });
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";

    if (!apiKey) {
      return new Response(JSON.stringify({ error: "Missing OPENAI_API_KEY secret." }), {
        status: 500,
        headers: safeJsonHeaders(),
      });
    }

    // Extract viewer ID from JWT for identity context
    const authHeader = req.headers.get("authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    
    let callerId: string | null = null;
    if (jwt) {
      try {
        const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
        const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
        if (supabaseUrl && anonKey) {
          const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2");
          const supabase = createClient(supabaseUrl, anonKey);
          const { data: userData } = await supabase.auth.getUser(jwt);
          callerId = userData?.user?.id ?? null;
        }
      } catch (e) {
        console.log("arlo-member-chat: Could not extract viewer ID", String(e));
      }
    }

    const memberId = String(body?.member_id ?? "");
    const isViewingSelf = callerId && memberId && callerId === memberId;

    // Build identity-aware context
    const identityContext = isViewingSelf
      ? "You are discussing the viewer's own health data. Use 'you' and 'your' when referring to them."
      : `You are discussing ${memberName}'s health with someone who cares about them. Use '${memberName}' or appropriate relationship references.`;

    const intentGuide = getIntentGuide(intent);
    
    const system: ChatMessage = {
      role: "system",
      content: `
You are Miya: a warm, supportive family health coach.

${identityContext}

${intentGuide ? `SPECIFIC FOCUS: ${intentGuide}` : ""}

RESPONSE STYLE:
- Be conversational and natural - NO rigid sections or headers
- Adapt your response length to the question:
  * Simple questions: 40-80 words
  * Complex questions: 100-150 words
- Always ground responses in specific data from the member facts when available
- End with ONE follow-up question IF it helps the conversation (optional, not required)
- Vary your structure - sometimes lead with insight, sometimes with data, sometimes with action
- Build on the conversation - don't repeat what you just said

RESPONSE PATTERNS (use naturally, don't force):
- For "doing well" questions: Start with the strength, back it with data, explain why it matters
- For "needs support" questions: Acknowledge the concern, provide specific data, suggest one clear action
- For pillar-specific questions: Focus on that pillar only, reference current values and recent changes
- For follow-up questions: Build on what you just discussed, go deeper, don't restart

CRITICAL: Each response must feel unique and conversational. No templates, no rigid formats.
`.trim(),
    };
    
    console.log(`arlo-member-chat: isViewingSelf=${isViewingSelf} (callerId=${callerId}, memberId=${memberId})`);

    // Build member facts system message if available
    const factsLines: string[] = [];
    if (facts) {
      factsLines.push(`Member Data for ${facts.memberName}:`);
      
      if (facts.vitalityScore !== undefined) {
        const delta = facts.vitalityDeltaPercent 
          ? ` (${facts.vitalityDeltaPercent > 0 ? '+' : ''}${facts.vitalityDeltaPercent}%)` 
          : "";
        factsLines.push(`Vitality Score: ${facts.vitalityScore}${delta}`);
      }
      
      if (facts.sleepValue) {
        factsLines.push(`Sleep: ${facts.sleepValue}${facts.sleepChangeText ? ` — ${facts.sleepChangeText}` : ""}`);
      }
      
      if (facts.movementValue) {
        factsLines.push(`Movement: ${facts.movementValue}${facts.movementChangeText ? ` — ${facts.movementChangeText}` : ""}`);
      }
      
      if (facts.recoveryValue) {
        factsLines.push(`Recovery: ${facts.recoveryValue}${facts.recoveryChangeText ? ` — ${facts.recoveryChangeText}` : ""}`);
      }
    }

    const factsMessage: ChatMessage | null = factsLines.length > 1
      ? { role: "system", content: factsLines.join("\n") }
      : null;

    // Keep last 10 messages for context (prevent token bloat)
    const recentMessages = messages
      .filter((m) => typeof m.content === "string" && m.content.trim().length > 0)
      .slice(-10);

    const input: ChatMessage[] = [
      system,
      ...(factsMessage ? [factsMessage] : []),
      ...recentMessages,
    ];

    console.log("arlo-member-chat: calling openai", { model, inputCount: input.length, member: memberName });

    // OpenAI call with timeout
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
          max_tokens: 300,  // Increased for variable-length conversational responses
        }),
        signal: controller.signal,
      });
    } catch (err) {
      const msg = String(err);
      const isAbort = msg.toLowerCase().includes("abort");

      console.log("arlo-member-chat: openai fetch threw", msg);

      return new Response(
        JSON.stringify({
          reply: isAbort
            ? `Sorry — that took too long. Let's try again. What about ${memberName}'s health would you like to focus on?`
            : `Sorry — I couldn't reach the coach right now. Try again in a moment.`,
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
          reply: `I couldn't generate that just now. What aspect of ${memberName}'s health would you like to explore?`,
          status: resp.status,
        }),
        { status: 200, headers: safeJsonHeaders() },
      );
    }

    // Extract reply from OpenAI Chat Completions response
    const reply = (data?.choices?.[0]?.message?.content?.trim()) || 
      `Sorry — I couldn't generate a reply about ${memberName}.`;

    // Generate contextual follow-up pills based on what Miya JUST said
    const suggestedPrompts = generateResponseAwarePills(
      memberName,
      reply,  // Pass the actual AI response to analyze
      intent,
      facts,
      recentMessages
    );

    console.log("arlo-member-chat: done, ms", Date.now() - t0, "pills", suggestedPrompts.length);

    return new Response(
      JSON.stringify({
        reply,
        suggested_prompts: suggestedPrompts
      }),
      { status: 200, headers: safeJsonHeaders() },
    );
  } catch (e) {
    console.log("arlo-member-chat: unhandled error", String(e));

    return new Response(
      JSON.stringify({
        reply: "Sorry — something went wrong. Try again or ask about sleep, movement, or recovery.",
        error: "Unhandled error",
      }),
      { status: 200, headers: safeJsonHeaders() },
    );
  }
});
