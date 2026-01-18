// Miya Insight Chat (GPT) - contextual Q&A about a specific pattern alert.
// Input: { alert_state_id: string, message: string }
//
// Secrets:
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE_KEY
// - SUPABASE_ANON_KEY
// - OPENAI_API_KEY
// Optional:
// - OPENAI_MODEL_CHAT (default: gpt-4.1-mini)
// - MIYA_AI_ENABLED (default: true)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function requireEnv(name: string): string {
  const v = Deno.env.get(name);
  if (!v) throw new Error(`Missing env var: ${name}`);
  return v;
}

async function callOpenAI(args: {
  apiKey: string;
  model: string;
  system: string;
  messages: Array<{ role: "user" | "assistant"; content: string }>;
}): Promise<string> {
  const { apiKey, model, system, messages } = args;
  
  // Use correct OpenAI Chat Completions API
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { 
      Authorization: `Bearer ${apiKey}`, 
      "Content-Type": "application/json" 
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        ...messages
      ],
      temperature: 0.7,
      max_tokens: 800,  // Reasonable limit for chat responses
    }),
  });
  
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`OpenAI error: ${res.status} ${txt}`);
  }
  
  const data = await res.json();
  const content = data?.choices?.[0]?.message?.content;
  
  if (!content) {
    throw new Error("OpenAI response missing content");
  }
  
  return content;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ ok: false, message: "Method not allowed" }, 405);

  try {
    const enabled = (Deno.env.get("MIYA_AI_ENABLED") ?? "true").toLowerCase() !== "false";
    if (!enabled) return jsonResponse({ ok: false, error: "AI disabled" }, 503);

    const supabaseUrl = requireEnv("SUPABASE_URL");
    const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = requireEnv("SUPABASE_ANON_KEY");

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7) : null;
    if (!token) return jsonResponse({ ok: false, error: "Missing bearer token" }, 401);

    const supabaseUserClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const supabaseAdmin = createClient(supabaseUrl, serviceKey);

    const { data: userData, error: userErr } = await supabaseUserClient.auth.getUser();
    if (userErr || !userData?.user) return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
    const callerId = userData.user.id;

    const body = await req.json().catch(() => null) as { 
      alert_state_id?: string; 
      message?: string;
      context?: any;      // Client-provided health context
      history?: any[];    // Client-provided conversation history
    } | null;
    const alertStateId = body?.alert_state_id;
    const message = (body?.message ?? "").trim();
    const clientContext = body?.context || {};
    const clientHistory = body?.history || [];
    if (!alertStateId) return jsonResponse({ ok: false, error: "Missing alert_state_id" }, 400);
    if (!message) return jsonResponse({ ok: false, error: "Missing message" }, 400);

    // Fetch alert row
    const { data: alert, error: alertErr } = await supabaseAdmin
      .from("pattern_alert_state")
      .select("id,user_id,metric_type,pattern_type,active_since,current_level,severity,last_evaluated_date")
      .eq("id", alertStateId)
      .maybeSingle();
    if (alertErr || !alert) return jsonResponse({ ok: false, error: "Alert not found" }, 404);

    // AuthZ: caller + member must share a family.
    const { data: callerFamilies, error: famErr } = await supabaseAdmin
      .from("family_members")
      .select("family_id")
      .eq("user_id", callerId);
    if (famErr) return jsonResponse({ ok: false, error: "Auth check failed" }, 403);
    const familyIds = (callerFamilies ?? []).map((r: any) => r.family_id).filter(Boolean);
    if (!familyIds.length) return jsonResponse({ ok: false, error: "Not in a family" }, 403);

    const { data: memberLink, error: memberErr } = await supabaseAdmin
      .from("family_members")
      .select("family_id")
      .eq("user_id", alert.user_id)
      .in("family_id", familyIds)
      .limit(1)
      .maybeSingle();
    if (memberErr || !memberLink) return jsonResponse({ ok: false, error: "Not authorized" }, 403);

    // Thread upsert
    const { data: thread, error: threadErr } = await supabaseAdmin
      .from("pattern_alert_ai_threads")
      .upsert({ alert_state_id: alertStateId, created_by: callerId }, { onConflict: "alert_state_id,created_by" })
      .select("id")
      .maybeSingle();
    if (threadErr || !thread?.id) return jsonResponse({ ok: false, error: "Thread error" }, 500);
    const threadId = thread.id;

    // Store user message
    await supabaseAdmin.from("pattern_alert_ai_messages").insert({ thread_id: threadId, role: "user", content: message });

    // Load cached insight evidence (best grounding)
    const { data: cached, error: cachedErr } = await supabaseAdmin
      .from("pattern_alert_ai_insights")
      .select("headline,summary,clinical_interpretation,data_connections,evidence")
      .eq("alert_state_id", alertStateId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (cachedErr || !cached) return jsonResponse({ ok: false, error: "Insight not generated yet" }, 409);

    // Load conversation history
    const { data: msgs } = await supabaseAdmin
      .from("pattern_alert_ai_messages")
      .select("role,content")
      .eq("thread_id", threadId)
      .order("created_at", { ascending: true })
      .limit(20);

    const system = `
You are Miya - a caring, knowledgeable health coach and trusted friend. You're talking with a caregiver about someone they love (the member). Your goal is to help them understand what's going on and support their family member together.

TONE & WARMTH:
- Talk like a supportive friend who happens to know health stuff
- Show you care - use "I can see...", "I notice...", "Let's figure this out together"
- Be reassuring but honest - it's okay to say "this is worth paying attention to"
- When things look good, celebrate it! "That's actually encouraging!"
- Use natural language - say "Hmm" or "Yeah" or "I get it"

YOUR APPROACH:
- ALWAYS START with their specific data, then supplement with general health knowledge when helpful
- Be ACTION-ORIENTED: Don't just explain the problem, provide concrete steps to improve it
- You have deep health expertise - use it! Explain mechanisms AND give practical recommendations
- Blend their situation with broader health science + actionable strategies
- Speak TO the caregiver ABOUT the member (third person: they/their, [Name]'s)
- No diagnosis or medication changes - you're a guide, not a doctor
- If something sounds serious (chest pain, fainting, etc.) → gently suggest getting professional help
- If you're not sure what they're asking → just ask them to clarify

CORE PRINCIPLE: Be a PROBLEM-SOLVER, not just an explainer
- When you see a problem (low sleep, low movement) → immediately offer 2-3 specific things they can try
- When asked "what's happening?" → explain briefly, then pivot to "here's what can help"
- Make recommendations SPECIFIC and ACTIONABLE (not "improve sleep hygiene" but "set bedtime alarm for 10pm, avoid screens 1hr before")

WHAT YOU CAN DO:
✅ Explain biological mechanisms (sleep → cortisol → fatigue → less movement)
✅ Give SPECIFIC, actionable recommendations (not just "improve sleep" but "try 10pm bedtime, 15-min walk after dinner")
✅ Share evidence-based strategies (sleep hygiene details, exercise timing, stress techniques with steps)
✅ Connect patterns to broader health science
✅ Cite research when relevant ("Studies show...", "Research suggests...")
✅ Provide implementation tips ("Start with just one change", "Best time is...", "If she resists, try...")

WHAT YOU CANNOT DO:
❌ Diagnose medical conditions or make up data you weren't given
❌ Prescribe medications, supplements, or replace medical professionals
❌ Ignore their specific numbers - always tie back to their case
❌ Give vague advice ("be healthier", "rest more") - be SPECIFIC
❌ Just explain without offering solutions

HOW TO FORMAT:
- Use **bold** for important numbers ("**6.4 hours**", "**31/100**")
- Use bullets when you have 2+ things to share (keeps it scannable)
- Add subtle icons: 💤 (sleep), 🏃 (movement), ❤️ (heart), 📉 (decline), 📈 (improvement)
- Keep bullets short (1 sentence each, max 3-4 bullets)
- Always end with a question or next step to keep the conversation going

EXAMPLES OF YOUR VOICE:

User: "Is this serious?"
YOU: "I can see why you're concerned. Gulmira's sleep score has dropped from **77/100 to 31/100** over the last 9 days - that's significant. Here's what I recommend we tackle first:

• 💤 **Set a consistent bedtime** - Pick a time (like 10:30pm) and stick to it, even on weekends
• 🏃 **Add a 15-min walk** - Ideally after lunch or dinner, helps with sleep quality
• 📱 **Screen curfew** - No phones/TV 1 hour before bed (blue light disrupts melatonin)

Start with just ONE of these - which feels most doable for Gulmira's routine?"

User: "What's happening with her movement?"
YOU: "Looking at her data, Gulmira's movement has dropped **43% below baseline** over the last 7 days. This is likely connected to her poor sleep (fatigue = less motivation to move). Here's what can help break this cycle:

• 🏃 **Morning movement** - Just 10 minutes after waking up boosts energy all day
• ⏰ **Set movement reminders** - Every 2 hours, encourage a quick walk or stretch
• 👟 **Make it easy** - Put walking shoes by the door, suggest walking during phone calls

The key is starting small. Even 5-10 minutes makes a difference. What part of her day has the most flexibility?"

User: "So you're saying more caffeine?"
YOU: "Actually, I'd avoid that. With her sleep at **6.4 hours** (needs 7-9), caffeine will make it worse. Instead, try these for natural energy:

• 🌞 **Morning sunlight** - 10 minutes outside within 1 hour of waking helps regulate her circadian rhythm
• 💧 **Hydration first** - Drink 16oz water before coffee (dehydration causes fatigue)
• 🏃 **Quick movement** - 5-min walk or stretches when energy dips

These boost energy without disrupting sleep. Which seems easiest to try first?"

User: "What does this data mean?"
YOU: "These are Gulmira's Sleep Vitality Scores (0-100 scale, higher = better). I see big swings - **31, 52, 81** - which means something's inconsistent. Here's what usually causes this:

• ⏰ **Irregular bedtime** - Going to bed at different times each night
• 📱 **Screen time varies** - Some nights on phone late, others not
• 🍷 **Weekend habits** - Alcohol, late meals, or staying up later

Let's identify the pattern. Does Gulmira have a consistent bedtime, or does it vary a lot?"

CRITICAL: SUGGESTED FOLLOW-UPS
After EVERY response, suggest 2-3 relevant follow-up questions the caregiver might want to ask next. These should:
- Flow naturally from what you just said
- Be specific and actionable (not generic)
- Help them dig deeper or take action
- Be short (5-8 words max per question)

Format them EXACTLY like this at the END of your response:

SUGGESTED_PROMPTS:
- [First specific question]
- [Second specific question]
- [Third specific question]

Example:
If you said "Gulmira's sleep has dropped to 31/100", suggest:
SUGGESTED_PROMPTS:
- How do we fix this?
- What's causing the drop?
- Should I be worried?

If you suggested bedtime consistency, suggest:
SUGGESTED_PROMPTS:
- How do I set a sleep schedule?
- What if she resists change?
- How long until we see improvement?

ALWAYS include SUGGESTED_PROMPTS at the end. They guide the conversation forward.

REMEMBER YOUR MISSION:
- You're not just explaining data - you're helping them IMPROVE their family member's health
- Every response should move them toward ACTION (what to do, how to do it, when to start)
- Be specific: Not "improve sleep" but "try 10:30pm bedtime + 1hr screen curfew"
- Make it easy: "Start with just ONE change", "Pick the easiest one first"
- Be warm, be real, be helpful. Keep responses grounded in their data, but focused on SOLUTIONS.
`.trim();

    // Use client-provided context if available (more efficient), otherwise fetch from evidence
    let memberName: string;
    let healthInsight: any;
    
    if (clientContext && Object.keys(clientContext).length > 0) {
      // Client sent full context - use it directly
      memberName = (clientContext.member_name || "").split(" ")[0] || "the family member";
      
      // Extract specific numbers from recent values for clear reference
      const recentValues = clientContext.recent_daily_values || [];
      const valuesArray = recentValues.map((d: any) => d.value).filter((v: any) => v != null);
      const avgRecent = valuesArray.length > 0 ? Math.round(valuesArray.reduce((a: number, b: number) => a + b) / valuesArray.length) : null;
      
      const metricName = clientContext.metric_name || 'Unknown Metric';
      const metricUnit = clientContext.metric_unit || '';
      
      // Determine if this is a score (0-100) or a measurement (actual units)
      const isScore = metricUnit === '/100' || metricName.toLowerCase().includes('score');
      const unitDisplay = metricUnit === '/100' ? '/100' : ` ${metricUnit}`;
      
      healthInsight = {
        member: { name: memberName },
        metric: {
          name: metricName,
          unit: metricUnit,
          isScore: isScore,
          description: isScore 
            ? `All values are ${metricName} (0-100 scale, higher is better)`
            : `All values are measured in ${metricUnit} and represent ${metricName}`
        },
        timeframe: `last ${clientContext.duration_days || 'several'} days`,
        alert: clientContext.alert_headline || cached.headline,
        severity: clientContext.severity || 'unknown',
        specificData: {
          currentAverage: avgRecent ? `${avgRecent}${unitDisplay}` : null,
          optimalRange: clientContext.optimal_range ? `${clientContext.optimal_range.min}-${clientContext.optimal_range.max}${unitDisplay}` : null,
          dailyValues: recentValues.slice(-7).map((d: any) => ({
            date: d.date,
            value: d.value != null ? `${d.value}${unitDisplay}` : 'no data'
          })),
        },
        keyFindings: [
          ...(clientContext.clinical_interpretation ? [clientContext.clinical_interpretation] : []),
          ...(clientContext.data_connections ? [clientContext.data_connections] : []),
        ].filter(Boolean),
        whatToReference: isScore
          ? `CRITICAL: These values are ${metricName} on a 0-100 scale (higher = better). When showing daily values, say things like "score of 81/100" or "31/100". Current average: ${avgRecent}/100, optimal: ${clientContext.optimal_range?.min}-${clientContext.optimal_range?.max}/100. NEVER say "hours" or other measurement units for scores.`
          : `CRITICAL: These values are ${metricName} measured in ${metricUnit}. Current average: ${avgRecent} ${metricUnit}, optimal: ${clientContext.optimal_range?.min}-${clientContext.optimal_range?.max} ${metricUnit}. ALWAYS include the metric name and unit.`
      };
    } else {
      // Fall back to fetching from cached evidence (old behavior)
      memberName = ((cached.evidence as any)?.person?.name ?? "").split(" ")[0] || "the family member";
      const alertInfo = (cached.evidence as any)?.alert || {};
      const primaryMetric = (cached.evidence as any)?.primary_metric || {};
      const supportingMetrics = (cached.evidence as any)?.supporting_metrics || [];
      const contextInfo = (cached.evidence as any)?.context || {};
      
      healthInsight = {
        member: { name: memberName },
        timeframe: `last ${alertInfo.consecutive_days || 'several'} days`,
        alert: cached.headline,
        keyFindings: [
          `${primaryMetric.name || 'metric'}: baseline ${primaryMetric.baseline_value || 'unknown'}, current ${primaryMetric.current_value || 'unknown'} (${primaryMetric.percent_change || '0'}% change)`,
          ...(cached.clinical_interpretation ? [cached.clinical_interpretation.slice(0, 150)] : []),
        ].filter(Boolean),
        supportingData: supportingMetrics.slice(0, 3).map((m: any) => 
          `${m.name}: ${m.current_value || 'N/A'} (baseline: ${m.baseline_value || 'N/A'})`
        ),
        caveats: [
          ...(contextInfo.days_missing > 5 ? [`${contextInfo.days_missing} days of data missing`] : []),
          ...(supportingMetrics.length === 0 ? ['Limited supporting metrics available'] : []),
        ].filter(Boolean),
      };
    }
    
    // Extract member health profile if available
    const memberHealthProfile = clientContext?.member_health_profile || {};
    
    // Build health profile summary for AI
    let healthProfileText = '';
    if (Object.keys(memberHealthProfile).length > 0) {
      const parts: string[] = [];
      
      // Demographics
      if (memberHealthProfile.age) parts.push(`${memberHealthProfile.age} years old`);
      if (memberHealthProfile.gender) parts.push(`${memberHealthProfile.gender}`);
      
      // Physical measurements
      if (memberHealthProfile.bmi) {
        parts.push(`BMI: ${memberHealthProfile.bmi}`);
      } else if (memberHealthProfile.weight_kg && memberHealthProfile.height_cm) {
        parts.push(`${memberHealthProfile.weight_kg}kg, ${memberHealthProfile.height_cm}cm`);
      }
      
      // Risk assessment
      if (memberHealthProfile.risk_band) {
        parts.push(`Cardiovascular risk: ${memberHealthProfile.risk_band}`);
      }
      if (memberHealthProfile.optimal_vitality_target) {
        parts.push(`Target vitality score: ${memberHealthProfile.optimal_vitality_target}/100`);
      }
      
      // Health conditions
      const conditions: string[] = [];
      if (memberHealthProfile.blood_pressure_status && memberHealthProfile.blood_pressure_status !== 'normal') {
        conditions.push(`BP: ${memberHealthProfile.blood_pressure_status}`);
      }
      if (memberHealthProfile.diabetes_status && memberHealthProfile.diabetes_status !== 'none') {
        conditions.push(`Diabetes: ${memberHealthProfile.diabetes_status}`);
      }
      if (memberHealthProfile.smoking_status && memberHealthProfile.smoking_status !== 'never') {
        conditions.push(`Smoking: ${memberHealthProfile.smoking_status}`);
      }
      if (memberHealthProfile.has_prior_heart_attack) {
        conditions.push('Prior heart attack');
      }
      if (memberHealthProfile.has_prior_stroke) {
        conditions.push('Prior stroke');
      }
      
      // Family history
      const familyHistory: string[] = [];
      if (memberHealthProfile.family_heart_disease_early) {
        familyHistory.push('early heart disease');
      }
      if (memberHealthProfile.family_stroke_early) {
        familyHistory.push('early stroke');
      }
      if (memberHealthProfile.family_type2_diabetes) {
        familyHistory.push('type 2 diabetes');
      }
      
      if (parts.length > 0) {
        healthProfileText = `\n\nMEMBER HEALTH PROFILE:\n${parts.join(', ')}`;
      }
      if (conditions.length > 0) {
        healthProfileText += `\nHealth conditions: ${conditions.join(', ')}`;
      }
      if (familyHistory.length > 0) {
        healthProfileText += `\nFamily history: ${familyHistory.join(', ')}`;
      }
      
      healthProfileText += '\n\nUSE THIS CONTEXT: When making recommendations, consider their age, risk profile, and health conditions. Tailor advice to their specific situation (e.g., gentler recommendations for higher risk individuals, age-appropriate suggestions).';
    }
    
    // Add structured context as "source of truth"
    const systemWithContext = system + `

HEALTH INSIGHT (source of truth):
${JSON.stringify(healthInsight, null, 2)}${healthProfileText}

Only reference data from above. If asked about something not listed, say you don't have that data.`;

    // Use client-provided history if available (includes full conversation state)
    // Otherwise fall back to database messages
    const chatMessages: Array<{ role: "user" | "assistant"; content: string }> = 
      clientHistory.length > 0 
        ? clientHistory.map((m: any) => ({ 
            role: m.role === "assistant" ? "assistant" : "user", 
            content: m.text 
          }))
        : (msgs ?? []).map((m: any) => ({ role: m.role, content: m.content }));

    const openaiKey = requireEnv("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL_CHAT") ?? "gpt-4o"; // Use best conversational model
    const reply = await callOpenAI({ apiKey: openaiKey, model, system: systemWithContext, messages: chatMessages });

    await supabaseAdmin.from("pattern_alert_ai_messages").insert({ thread_id: threadId, role: "assistant", content: reply });

    return jsonResponse({ ok: true, reply });
  } catch (e) {
    console.error("MIYA_INSIGHT_CHAT_ERROR", String(e));
    return jsonResponse({ ok: false, error: String(e) }, 500);
  }
});

