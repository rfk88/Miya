// Miya Insight (GPT) - generates evidence-grounded family insight for a pattern alert.
// Input: { alert_state_id: string }
// Output: JSON with headline/summary/actions/message suggestions + evidence.
//
// Secrets (Supabase Edge Function):
// - SUPABASE_URL
// - SUPABASE_SERVICE_ROLE_KEY
// - SUPABASE_ANON_KEY
// - OPENAI_API_KEY
// Optional:
// - OPENAI_MODEL_INSIGHT (default: gpt-4.1-mini)
// - MIYA_AI_ENABLED (default: true)
// - MIYA_AI_LOG_PAYLOADS (default: false)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, apikey",
};

type InsightResponse = {
  headline: string;
  clinical_interpretation: string;
  data_connections: string;
  possible_causes: string[];
  action_steps: string[];
  message_suggestions?: { label: string; text: string }[];
  confidence?: "low" | "medium" | "high";
  confidence_reason?: string;
  evidence: Record<string, unknown>;
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

function toYYYYMMDD(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function addDaysUTC(dayKey: string, days: number): string {
  const d = new Date(`${dayKey}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return toYYYYMMDD(d);
}

function clampEndDateToToday(dayKey: string): string {
  const today = toYYYYMMDD(new Date());
  return dayKey > today ? today : dayKey;
}

function pct(n: number): string {
  return `${Math.round(n * 100)}%`;
}

function firstName(fullName: string): string {
  return fullName.split(" ").filter(Boolean)[0] ?? fullName;
}

function metricDisplay(metric: string): string {
  switch (metric) {
    case "sleep_minutes":
      return "Sleep";
    case "steps":
      return "Movement";
    case "hrv_ms":
      return "HRV";
    case "resting_hr":
      return "Resting HR";
    default:
      return "Health";
  }
}

function unitForMetric(metric: string): string {
  switch (metric) {
    case "sleep_minutes":
      return "min";
    case "steps":
      return "steps";
    case "hrv_ms":
      return "ms";
    case "resting_hr":
      return "bpm";
    default:
      return "";
  }
}

function patternVerb(patternType: string | null): { verb: string; direction: "down" | "up" } {
  const p = (patternType ?? "").toLowerCase();
  if (p.includes("rise")) return { verb: "above baseline", direction: "up" };
  return { verb: "below baseline", direction: "down" };
}

function avg(nums: number[]): number | null {
  if (!nums.length) return null;
  return nums.reduce((a, b) => a + b, 0) / nums.length;
}

function pctChange(baseline: number | null, recent: number | null): number | null {
  if (baseline == null || recent == null || baseline === 0) return null;
  return (recent - baseline) / baseline;
}

function severityLabel(sev: string | null, level: number): "watch" | "attention" | "critical" {
  const s = (sev ?? "").toLowerCase();
  if (s === "watch" || s === "attention" || s === "critical") return s;
  if (level >= 14) return "critical";
  if (level >= 7) return "attention";
  return "watch";
}

function buildMessageSuggestions(args: {
  memberFirstName: string;
  metric: string;
  level: number;
  severity: "watch" | "attention" | "critical";
}): { label: string; text: string }[] {
  const { memberFirstName, metric, level, severity } = args;
  const m = metricDisplay(metric);
  const duration = `${level} days`;
  if (severity === "critical") {
    return [
      { label: "Supportive", text: `Hey ${memberFirstName} — I noticed your ${m.toLowerCase()} has been off your usual baseline for a while (${duration}). How are you feeling? Want to chat today?` },
      { label: "Practical", text: `Hey ${memberFirstName}, checking in. Your ${m.toLowerCase()} looks lower than usual recently (${duration}). Anything stressful or affecting sleep/routine?` },
      { label: "Simple", text: `Thinking of you, ${memberFirstName}. How are you feeling lately?` },
    ];
  }
  if (severity === "attention") {
    return [
      { label: "Supportive", text: `Hey ${memberFirstName} — quick check-in. Your ${m.toLowerCase()} has been trending away from your baseline this week (${duration}). Anything I can do to support you?` },
      { label: "Curious", text: `Hey ${memberFirstName}, have you noticed anything different in sleep/stress/routine this week?` },
      { label: "Low effort", text: `Hey ${memberFirstName} — just checking in. How are you doing today?` },
    ];
  }
  return [
    { label: "Gentle", text: `Hey ${memberFirstName} — quick check-in. I noticed your ${m.toLowerCase()} looks a bit different from usual over the last few days. How are you feeling?` },
    { label: "Simple", text: `Hey ${memberFirstName} — how’s your day going?` },
    { label: "Support", text: `Thinking of you, ${memberFirstName}. Anything you need right now?` },
  ];
}

async function callOpenAI(args: {
  apiKey: string;
  model: string;
  evidence: Record<string, unknown>;
}): Promise<Omit<InsightResponse, "evidence">> {
  const { apiKey, model, evidence } = args;

  const jsonSchema = {
    type: "object",
    additionalProperties: false,
    properties: {
      headline: { type: "string" },
      clinical_interpretation: { type: "string" },
      data_connections: { type: "string" },
      possible_causes: { type: "array", items: { type: "string" } },
      action_steps: { type: "array", items: { type: "string" } },
      message_suggestions: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          properties: { label: { type: "string" }, text: { type: "string" } },
          required: ["label", "text"],
        },
      },
      confidence: { type: "string", enum: ["low", "medium", "high"] },
      confidence_reason: { type: "string" },
    },
    required: ["headline", "clinical_interpretation", "data_connections", "possible_causes", "action_steps", "message_suggestions", "confidence", "confidence_reason"],
  } as const;

  // Extract data from new evidence structure
  const alert = (evidence.alert as any) || {};
  const person = (evidence.person as any) || {};
  const primaryMetric = (evidence.primary_metric as any) || {};
  const supportingMetrics = (evidence.supporting_metrics as any[]) || [];
  
  const memberFirstName = person.name || "Member";
  const metricName = alert.metric || "unknown";
  const pattern = alert.pattern || "drop_vs_baseline";
  const level = alert.level || 3;
  const consecutiveDays = alert.consecutive_days || 3;
  
  // Build metric-specific clinical interpretation template
  const getClinicalTemplate = () => {
    const pct = Math.abs(primaryMetric?.percent_change || 0);
    const baseline = primaryMetric?.baseline_value || 0;
    const current = primaryMetric?.current_value || 0;
    
    switch (metricName) {
      case "steps":
        return `A ${pct.toFixed(1)}% sustained decrease in daily steps (from ${Math.round(baseline)} to ${Math.round(current)} steps) over ${consecutiveDays} days is clinically significant. This level of reduction typically indicates injury, illness, lifestyle disruption, or changes in mental health and motivation.`;
      
      case "movement_minutes":
        const baselineMovementHours = (baseline / 60).toFixed(1);
        const currentMovementHours = (current / 60).toFixed(1);
        return `A ${pct.toFixed(1)}% decrease in active movement time (from ${baselineMovementHours} to ${currentMovementHours} hours) over ${consecutiveDays} days indicates reduced physical activity. This may reflect injury, illness, schedule changes, or decreased motivation. Movement minutes capture actual active time, not just steps.`;
      
      case "sleep_minutes":
        const baselineHours = (baseline / 60).toFixed(1);
        const currentHours = (current / 60).toFixed(1);
        return `A ${pct.toFixed(1)}% decrease in sleep duration (from ${baselineHours} to ${currentHours} hours) over ${consecutiveDays} days is concerning. Chronic sleep restriction increases cardiovascular and metabolic health risks and often signals stress, schedule changes, or emerging sleep disorders.`;
      
      case "sleep_efficiency_pct":
        return `A ${pct.toFixed(1)}% decrease in sleep efficiency (from ${Math.round(baseline)}% to ${Math.round(current)}%) over ${consecutiveDays} days indicates more time spent awake in bed relative to total sleep. Lower efficiency suggests fragmented sleep, frequent awakenings, or difficulty falling asleep, which can impact recovery and daytime function.`;
      
      case "deep_sleep_minutes":
        const baselineDeepHours = (baseline / 60).toFixed(1);
        const currentDeepHours = (current / 60).toFixed(1);
        return `A ${pct.toFixed(1)}% decrease in deep sleep (from ${baselineDeepHours} to ${currentDeepHours} hours) over ${consecutiveDays} days is significant. Deep sleep is critical for physical recovery, immune function, and memory consolidation. Reduced deep sleep often indicates stress, alcohol use, or sleep disorders.`;
      
      case "rem_sleep_minutes":
        const baselineRemHours = (baseline / 60).toFixed(1);
        const currentRemHours = (current / 60).toFixed(1);
        return `A ${pct.toFixed(1)}% decrease in REM sleep (from ${baselineRemHours} to ${currentRemHours} hours) over ${consecutiveDays} days may affect cognitive function and emotional regulation. REM sleep supports memory, learning, and mood. Reductions often occur with sleep restriction, alcohol, or certain medications.`;
      
      case "hrv_ms":
      case "hrv_rmssd_ms":
        return `A ${pct.toFixed(1)}% drop in heart rate variability (from ${Math.round(baseline)}ms to ${Math.round(current)}ms) over ${consecutiveDays} days indicates increased physiological stress. Lower HRV is associated with poor recovery, illness, overtraining, or psychological stress.`;
      
      case "resting_hr":
        return `A ${pct.toFixed(1)}% increase in resting heart rate (from ${Math.round(baseline)} to ${Math.round(current)} bpm) over ${consecutiveDays} days suggests reduced cardiovascular fitness, inadequate recovery, or potential illness. Elevated resting heart rate is an early warning sign the body isn't recovering properly.`;
      
      case "breaths_avg_per_min":
        return `A ${pct.toFixed(1)}% change in breathing rate (from ${Math.round(baseline)} to ${Math.round(current)} breaths/min) over ${consecutiveDays} days may indicate respiratory changes, stress, or sleep quality issues. Elevated breathing rate during sleep can signal sleep-disordered breathing or stress.`;
      
      case "spo2_avg_pct":
        return `A ${pct.toFixed(1)}% decrease in blood oxygen saturation (from ${Math.round(baseline)}% to ${Math.round(current)}%) over ${consecutiveDays} days is concerning. Lower SpO2 during sleep may indicate sleep apnea, respiratory issues, or altitude effects.`;
      
      case "calories_active":
        return `A ${pct.toFixed(1)}% decrease in active calories burned (from ${Math.round(baseline)} to ${Math.round(current)} kcal) over ${consecutiveDays} days reflects reduced physical activity levels. This may indicate injury, illness, schedule disruption, or decreased motivation.`;
      
      default:
        return `A significant change in health metrics over ${consecutiveDays} days requires attention.`;
    }
  };

  // Build metric-specific possible causes
  const getPossibleCauses = () => {
    switch (metricName) {
      case "steps":
        return [
          "Injury, pain, or physical limitation affecting mobility",
          "Illness or recovery from illness",
          "Major routine disruption (weather, work schedule change, travel)",
          "Low motivation, mood changes, or depressive symptoms",
          "Intentional rest period or lifestyle change"
        ];
      
      case "movement_minutes":
        return [
          "Injury or physical limitation reducing active time",
          "Illness, fatigue, or recovery period",
          "Schedule changes reducing time for physical activity",
          "Decreased motivation or mood affecting activity levels",
          "Weather, travel, or environmental factors limiting movement"
        ];
      
      case "sleep_minutes":
        return [
          "Increased stress or anxiety interfering with sleep",
          "Schedule changes, late-night obligations, or work demands",
          "Poor sleep environment (noise, light, temperature)",
          "Changes in caffeine, alcohol, or medication",
          "Possible emerging sleep disorder"
        ];
      
      case "sleep_efficiency_pct":
        return [
          "Frequent awakenings due to stress, anxiety, or environmental factors",
          "Difficulty falling asleep (increased time in bed before sleep)",
          "Sleep-disordered breathing causing frequent arousals",
          "Pain, discomfort, or medical conditions disrupting sleep",
          "Alcohol or medication effects fragmenting sleep"
        ];
      
      case "deep_sleep_minutes":
        return [
          "Increased stress or cortisol levels suppressing deep sleep",
          "Alcohol consumption (reduces deep sleep even if total sleep is maintained)",
          "Sleep-disordered breathing or frequent awakenings",
          "Late evening exercise or screen time affecting sleep architecture",
          "Age-related changes or medical conditions affecting deep sleep"
        ];
      
      case "rem_sleep_minutes":
        return [
          "Sleep restriction or insufficient total sleep time",
          "Alcohol consumption (suppresses REM sleep)",
          "Certain medications affecting sleep stages",
          "Sleep schedule disruptions or irregular bedtimes",
          "Sleep-disordered breathing interrupting REM cycles"
        ];
      
      case "hrv_ms":
      case "hrv_rmssd_ms":
        return [
          "Overtraining or insufficient recovery between workouts",
          "Increased psychological stress or anxiety",
          "Early signs of illness or inflammation",
          "Poor sleep quality affecting autonomic recovery",
          "Dietary changes or dehydration"
        ];
      
      case "resting_hr":
        return [
          "Reduced cardiovascular fitness from inactivity",
          "Inadequate recovery or cumulative fatigue",
          "Early illness or infection developing",
          "Increased stress or anxiety levels",
          "Dehydration or changes in medication"
        ];
      
      case "breaths_avg_per_min":
        return [
          "Sleep-disordered breathing or sleep apnea",
          "Stress or anxiety affecting respiratory rate",
          "Respiratory illness or congestion",
          "Altitude changes or environmental factors",
          "Medication side effects affecting breathing"
        ];
      
      case "spo2_avg_pct":
        return [
          "Sleep apnea or sleep-disordered breathing",
          "Respiratory illness or congestion",
          "Altitude changes or environmental factors",
          "Underlying respiratory or cardiovascular conditions",
          "Poor sleep position or airway obstruction"
        ];
      
      case "calories_active":
        return [
          "Reduced physical activity due to injury or pain",
          "Illness, fatigue, or recovery period",
          "Schedule changes reducing exercise opportunities",
          "Decreased motivation or mood affecting activity",
          "Environmental factors limiting physical activity"
        ];
      
      default:
        return ["Physical factors", "Mental factors", "Lifestyle changes"];
    }
  };

  // Build severity-aware action steps
  const getActionSteps = () => {
    const metricSigns = {
      steps: "persistent fatigue, pain, low mood, lack of motivation, social withdrawal",
      movement_minutes: "persistent fatigue, pain, low mood, lack of motivation, social withdrawal",
      sleep_minutes: "daytime fatigue, irritability, difficulty concentrating, increased caffeine use",
      sleep_efficiency_pct: "daytime fatigue, difficulty falling asleep, frequent awakenings, feeling unrested",
      deep_sleep_minutes: "daytime fatigue, poor physical recovery, feeling unrested despite adequate sleep time",
      rem_sleep_minutes: "difficulty concentrating, memory issues, mood changes, feeling emotionally unregulated",
      hrv_ms: "persistent fatigue, poor workout recovery, frequent illness, high stress levels",
      hrv_rmssd_ms: "persistent fatigue, poor workout recovery, frequent illness, high stress levels",
      resting_hr: "feeling unwell, persistent fatigue, difficulty with usual activities, chest discomfort",
      breaths_avg_per_min: "daytime fatigue, snoring, gasping during sleep, morning headaches",
      spo2_avg_pct: "daytime fatigue, morning headaches, difficulty concentrating, gasping during sleep",
      calories_active: "persistent fatigue, low energy, decreased motivation, weight changes"
    }[metricName] || "unusual symptoms";

    const metricAction = {
      steps: "Offer to take a short walk together, remove barriers to movement, adjust expectations",
      movement_minutes: "Offer to do activities together, remove barriers to movement, adjust expectations",
      sleep_minutes: "Review sleep routine together, adjust evening schedule, create better sleep environment",
      sleep_efficiency_pct: "Review sleep routine, address sleep environment, consider sleep hygiene practices",
      deep_sleep_minutes: "Review evening routine, reduce alcohol/caffeine, optimize sleep environment for deep sleep",
      rem_sleep_minutes: "Review sleep schedule, reduce alcohol, ensure adequate total sleep time",
      hrv_ms: "Encourage rest days, reduce training intensity, support stress management",
      hrv_rmssd_ms: "Encourage rest days, reduce training intensity, support stress management",
      resting_hr: "Ensure adequate hydration, encourage rest, monitor for illness symptoms",
      breaths_avg_per_min: "Review sleep position, consider sleep study, address potential sleep-disordered breathing",
      spo2_avg_pct: "Review sleep position, consider sleep study, address potential sleep-disordered breathing",
      calories_active: "Offer to do activities together, remove barriers to movement, adjust expectations"
    }[metricName] || "Provide support and monitor closely";

    if (level >= 14) {
      return [
        `Priority conversation with ${memberFirstName} TODAY - this pattern has been ongoing for ${consecutiveDays} days`,
        `Assess for warning signs: ${metricSigns}, changes in appetite, sleep disturbances`,
        `Take immediate action: ${metricAction}`,
        `Schedule medical consultation within 3-5 days if no clear cause identified or no improvement seen`
      ];
    } else if (level >= 7) {
      return [
        `Have a direct conversation with ${memberFirstName} today about how they're feeling physically and emotionally`,
        `Look for specific signs: ${metricSigns}`,
        `Take supportive action: ${metricAction}`,
        `If pattern continues another week, schedule a check-in with healthcare provider`
      ];
    } else {
      return [
        `Check in casually with ${memberFirstName} about how they've been feeling`,
        `Continue monitoring for another 2-3 days to see if pattern continues`,
        `No immediate action needed unless accompanied by other symptoms`,
        `Revisit if pattern persists into next week`
      ];
    }
  };

  let clinicalTemplate = "";
  try {
    clinicalTemplate = getClinicalTemplate();
  } catch (e) {
    console.error("getClinicalTemplate failed:", e);
    clinicalTemplate = `A significant change in ${metricName} over ${consecutiveDays} days requires attention.`;
  }

  let possibleCauses: string[] = [];
  try {
    possibleCauses = getPossibleCauses();
  } catch (e) {
    console.error("getPossibleCauses failed:", e);
    possibleCauses = ["Physical factors", "Mental factors", "Lifestyle changes"];
  }

  let actionSteps: string[] = [];
  try {
    actionSteps = getActionSteps();
  } catch (e) {
    console.error("getActionSteps failed:", e);
    actionSteps = [
      `Check in with ${memberFirstName} about how they're feeling`,
      "Monitor for any concerning symptoms",
      "Provide support as needed",
      "Consult healthcare provider if pattern persists"
    ];
  }

  const system = [
    "You are a family health advisor with clinical expertise analyzing wearable health data.",
    "",
    `PERSON: ${memberFirstName}`,
    `PRIMARY ALERT: ${metricName} showing ${pattern}`,
    `ALERT SEVERITY: Level ${level} (${consecutiveDays} consecutive days)`,
    "",
    "Generate a health insight following this exact structure:",
    "",
    "## CLINICAL INTERPRETATION (2-3 sentences)",
    `Use this template: "${clinicalTemplate}"`,
    "Adapt the numbers and wording based on the actual evidence data provided.",
    "",
    "## WHAT THE DATA SHOWS (2-3 sentences)",
    "Analyze ALL supporting metrics in supporting_metrics array. Prioritize rich metrics that provide deeper context:",
    "",
    "For SLEEP alerts:",
    "- Use deep_sleep_minutes, rem_sleep_minutes, light_sleep_minutes, sleep_efficiency_pct to understand sleep quality",
    "- Example: 'Sleep duration decreased, but deep sleep increased from 1.2 to 1.5 hours, suggesting better sleep quality despite less total time.'",
    "",
    "For MOVEMENT/ACTIVITY alerts:",
    "- Use movement_minutes (active time) and calories_active alongside steps to understand activity patterns",
    "- Example: 'Steps decreased, but movement_minutes increased from 45 to 60 minutes, indicating longer but less frequent activity sessions.'",
    "",
    "For RECOVERY/STRESS alerts:",
    "- Use hrv_rmssd_ms, resting_hr, breaths_avg_per_min, spo2_avg_pct to understand recovery signals",
    "- Example: 'HRV decreased from 50ms to 42ms, while resting HR increased from 58 to 65 bpm, indicating elevated stress and reduced recovery.'",
    "",
    "General guidelines:",
    "- Do supporting metrics support or contradict the primary alert?",
    "- What pattern emerges across all metrics?",
    "- ALWAYS use absolute values with units, NOT just percentages",
    "- Convert sleep_minutes, deep_sleep_minutes, rem_sleep_minutes to hours (divide by 60)",
    "- Reference specific supporting metrics by name when they provide meaningful context",
    "",
    "## POSSIBLE CAUSES (3-5 bullet points)",
    `Based on primary metric ${metricName}, include these realistic explanations:`,
    ...possibleCauses.map(c => `- ${c}`),
    "",
    "## RECOMMENDED ACTIONS (4 numbered steps)",
    `Urgency level: ${level >= 14 ? "CRITICAL" : level >= 7 ? "ATTENTION" : "WATCH"}`,
    ...actionSteps.map((s, i) => `${i + 1}. ${s}`),
    "",
    "## TONE GUIDELINES:",
    "- Be concerned and caring but not alarmist",
    "- Use 'may indicate' or 'often suggests' rather than 'definitely means'",
    "- Speak family-to-family, not doctor-to-patient",
    "- Match urgency to the alert level",
    "- Empower action without creating anxiety",
    "- Avoid medical jargon unless necessary",
    "",
    "You MUST ground all claims in the provided evidence JSON. Return valid JSON matching the provided schema only.",
  ].join("\n");

  const user = [
    `EVIDENCE_JSON:`,
    JSON.stringify(evidence, null, 2),
    "",
    `Generate insight for ${memberFirstName}'s ${metricName} alert (${pattern}, level ${level}, ${consecutiveDays} consecutive days).`,
    "",
    "Return JSON with: headline, clinical_interpretation, data_connections, possible_causes (array), action_steps (array), message_suggestions (array of {label, text}), confidence, confidence_reason.",
  ].join("\n");

  // Use correct OpenAI Chat Completions API with structured output
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "miya_pattern_insight",
          schema: jsonSchema,
          strict: true,
        },
      },
      temperature: 0.7,
    }),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`OpenAI error: ${res.status} ${txt}`);
  }

  const data = await res.json();
  const content = data?.choices?.[0]?.message?.content;

  if (!content) throw new Error("OpenAI response missing content");
  return JSON.parse(content);
}

Deno.serve(async (req) => {
  console.log("🎯 MIYA_INSIGHT: Request received", {
    method: req.method,
    url: req.url,
    headers: Object.fromEntries(req.headers.entries()),
  });

  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ ok: false, message: "Method not allowed" }, 405);

  try {
    const enabled = (Deno.env.get("MIYA_AI_ENABLED") ?? "true").toLowerCase() !== "false";
    const logPayloads = (Deno.env.get("MIYA_AI_LOG_PAYLOADS") ?? "false").toLowerCase() === "true";

    console.log("🔧 MIYA_INSIGHT: Config", { enabled, logPayloads });

    const supabaseUrl = requireEnv("SUPABASE_URL");
    const serviceKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = requireEnv("SUPABASE_ANON_KEY");

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7) : null;
    if (!token) {
      console.error("❌ MIYA_INSIGHT: Missing bearer token");
      return jsonResponse({ ok: false, error: "Missing bearer token" }, 401);
    }

    const supabaseUserClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const supabaseAdmin = createClient(supabaseUrl, serviceKey);

    const { data: userData, error: userErr } = await supabaseUserClient.auth.getUser();
    if (userErr || !userData?.user) {
      console.error("❌ MIYA_INSIGHT: Auth failed", { error: userErr });
      return jsonResponse({ ok: false, error: "Unauthorized" }, 401);
    }
    const callerId = userData.user.id;
    console.log("✅ MIYA_INSIGHT: Authenticated", { callerId });

    const body = await req.json().catch(() => null) as { alert_state_id?: string } | null;
    const alertStateId = body?.alert_state_id;
    console.log("📦 MIYA_INSIGHT: Request body", { body, alertStateId });
    
    if (!alertStateId) {
      console.error("❌ MIYA_INSIGHT: Missing alert_state_id");
      return jsonResponse({ ok: false, error: "Missing alert_state_id" }, 400);
    }

    // Fetch alert row
    const { data: alert, error: alertErr } = await supabaseAdmin
      .from("pattern_alert_state")
      .select("id,user_id,metric_type,pattern_type,episode_status,active_since,last_evaluated_date,current_level,severity,baseline_value,recent_value,deviation_percent")
      .eq("id", alertStateId)
      .maybeSingle();
    if (alertErr || !alert) return jsonResponse({ ok: false, error: "Alert not found" }, 404);

    const memberId: string = alert.user_id;
    const metricType: string = alert.metric_type;
    const patternType: string | null = alert.pattern_type ?? null;
    const level: number = alert.current_level ?? 3;
    const sev = severityLabel(alert.severity ?? null, level);

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
      .select("family_id,first_name")
      .eq("user_id", memberId)
      .in("family_id", familyIds)
      .limit(1)
      .maybeSingle();
    if (memberErr || !memberLink) return jsonResponse({ ok: false, error: "Not authorized" }, 403);

    const memberName = memberLink.first_name ?? "Member";
    const memberFirst = firstName(memberName);

    const evaluatedEnd = clampEndDateToToday(alert.last_evaluated_date ?? toYYYYMMDD(new Date()));
    const start = addDaysUTC(evaluatedEnd, -20);

    // Cache lookup (bump version when prompt/evidence changes)
    const promptVersion = "v4"; // v4 = metric-specific + severity-aware with all 4 metrics (primary + 3 supporting)
    const { data: cached, error: cacheErr } = await supabaseAdmin
      .from("pattern_alert_ai_insights")
      .select("headline,clinical_interpretation,data_connections,possible_causes,action_steps,message_suggestions,confidence,confidence_reason,evidence,model,prompt_version,created_at")
      .eq("alert_state_id", alertStateId)
      .eq("evaluated_end_date", evaluatedEnd)
      .eq("prompt_version", promptVersion)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    
    console.log("🔍 MIYA_INSIGHT: Cache query result", {
      alertStateId,
      found: !!cached,
      error: cacheErr?.message,
      cachedPromptVersion: cached?.prompt_version,
      hasClinical: !!cached?.clinical_interpretation,
      hasConnections: !!cached?.data_connections,
      hasCauses: !!cached?.possible_causes,
      hasActions: !!cached?.action_steps,
      createdAt: cached?.created_at,
    });
    if (cached && !cacheErr) {
      // Validate that the cached entry has the new format fields
      // If prompt_version = v4 but fields are missing, ignore cache (schema migration issue)
      const hasNewFields = cached.clinical_interpretation && cached.data_connections && 
                           cached.possible_causes && cached.action_steps;
      
      if (hasNewFields) {
        console.log("💾 MIYA_INSIGHT: Cache hit (valid)", { alertStateId, promptVersion });
        return jsonResponse({ ok: true, cached: true, ...cached });
      } else {
        console.log("⚠️ MIYA_INSIGHT: Cache hit but missing new fields, regenerating", { 
          alertStateId, 
          promptVersion,
          hasClinical: !!cached.clinical_interpretation,
          hasConnections: !!cached.data_connections,
          hasCauses: !!cached.possible_causes,
          hasActions: !!cached.action_steps,
        });
        // Delete the invalid cached entry
        await supabaseAdmin
          .from("pattern_alert_ai_insights")
          .delete()
          .eq("alert_state_id", alertStateId)
          .eq("evaluated_end_date", evaluatedEnd)
          .eq("prompt_version", promptVersion);
      }
    }
    
    console.log("🔄 MIYA_INSIGHT: Cache miss, generating new insight", { alertStateId, promptVersion });

    // Fetch raw metrics window (may include multiple rows/day from different sources)
    const { data: rawRows, error: rawErr } = await supabaseAdmin
      .from("wearable_daily_metrics")
      .select("metric_date,steps,movement_minutes,sleep_minutes,sleep_efficiency_pct,deep_sleep_minutes,rem_sleep_minutes,light_sleep_minutes,awake_minutes,hrv_ms,hrv_rmssd_ms,resting_hr,breaths_avg_per_min,spo2_avg_pct,calories_active,source")
      .eq("user_id", memberId)
      .gte("metric_date", start)
      .lte("metric_date", evaluatedEnd)
      .order("metric_date", { ascending: true });
    if (rawErr) return jsonResponse({ ok: false, error: "Failed to load metrics" }, 500);

    // Merge per day: choose row with most non-null fields.
    const byDay = new Map<string, any[]>();
    for (const r of rawRows ?? []) {
      const key = String(r.metric_date);
      byDay.set(key, [...(byDay.get(key) ?? []), r]);
    }
    const mergedSeries = [...byDay.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([day, rows]) => {
      const best = [...rows].sort((ra, rb) => {
        const ca = [
          ra.steps,
          ra.movement_minutes,
          ra.sleep_minutes,
          ra.sleep_efficiency_pct,
          ra.deep_sleep_minutes,
          ra.rem_sleep_minutes,
          ra.light_sleep_minutes,
          ra.awake_minutes,
          ra.hrv_ms,
          ra.hrv_rmssd_ms,
          ra.resting_hr,
          ra.breaths_avg_per_min,
          ra.spo2_avg_pct,
          ra.calories_active,
        ].filter((x) => x != null).length;
        const cb = [
          rb.steps,
          rb.movement_minutes,
          rb.sleep_minutes,
          rb.sleep_efficiency_pct,
          rb.deep_sleep_minutes,
          rb.rem_sleep_minutes,
          rb.light_sleep_minutes,
          rb.awake_minutes,
          rb.hrv_ms,
          rb.hrv_rmssd_ms,
          rb.resting_hr,
          rb.breaths_avg_per_min,
          rb.spo2_avg_pct,
          rb.calories_active,
        ].filter((x) => x != null).length;
        return cb - ca;
      })[0];
      return {
        date: day,
        steps: best?.steps ?? null,
        movement_minutes: best?.movement_minutes ?? null,
        sleep_minutes: best?.sleep_minutes ?? null,
        sleep_efficiency_pct: best?.sleep_efficiency_pct ?? null,
        deep_sleep_minutes: best?.deep_sleep_minutes ?? null,
        rem_sleep_minutes: best?.rem_sleep_minutes ?? null,
        light_sleep_minutes: best?.light_sleep_minutes ?? null,
        awake_minutes: best?.awake_minutes ?? null,
        hrv_ms: best?.hrv_ms ?? null,
        hrv_rmssd_ms: best?.hrv_rmssd_ms ?? null,
        resting_hr: best?.resting_hr ?? null,
        breaths_avg_per_min: best?.breaths_avg_per_min ?? null,
        spo2_avg_pct: best?.spo2_avg_pct ?? null,
        calories_active: best?.calories_active ?? null,
      };
    });

    const daysPresent = mergedSeries.length;
    const missingDays = 21 - daysPresent;

    const verb = patternVerb(patternType);
    const baselineVal: number | null = alert.baseline_value ?? null;
    const recentVal: number | null = alert.recent_value ?? null;
    const dev: number | null = alert.deviation_percent ?? null;

    type MetricKey =
      | "steps"
      | "movement_minutes"
      | "sleep_minutes"
      | "sleep_efficiency_pct"
      | "deep_sleep_minutes"
      | "rem_sleep_minutes"
      | "light_sleep_minutes"
      | "awake_minutes"
      | "hrv_ms"
      | "hrv_rmssd_ms"
      | "resting_hr"
      | "breaths_avg_per_min"
      | "spo2_avg_pct"
      | "calories_active";

    const valuesFor = (key: MetricKey) =>
      mergedSeries.map((d: any) => d[key]).filter((v: any) => typeof v === "number") as number[];
    
    const splitBaselineRecent = (vals: number[]) => {
      if (vals.length < 6) return { baseline: null as number | null, recent: null as number | null };
      const recent = vals.slice(-3);
      // Use up to 21 days for baseline (not just 7)
      const baseline = vals.slice(0, Math.min(21, Math.max(0, vals.length - 3)));
      return { baseline: avg(baseline), recent: avg(recent) };
    };

    // Compute baseline/recent for each metric we track
    const allMetrics: MetricKey[] = [
      "steps",
      "movement_minutes",
      "sleep_minutes",
      "sleep_efficiency_pct",
      "deep_sleep_minutes",
      "rem_sleep_minutes",
      "light_sleep_minutes",
      "awake_minutes",
      "hrv_ms",
      "hrv_rmssd_ms",
      "resting_hr",
      "breaths_avg_per_min",
      "spo2_avg_pct",
      "calories_active",
    ];
    const metricsData = allMetrics.map((m) => {
      const vals = valuesFor(m);
      const { baseline, recent } = splitBaselineRecent(vals);
      const deviation = pctChange(baseline, recent);
      const absoluteChange = (recent != null && baseline != null) ? recent - baseline : null;
      
      return {
        name: m,
        current_value: recent,
        baseline_value: baseline,
        percent_change: deviation != null ? Math.round(deviation * 100 * 10) / 10 : null, // Round to 1 decimal
        absolute_change: absoluteChange != null ? Math.round(absoluteChange * 10) / 10 : null,
      };
    });

    // Separate primary metric (the one that triggered alert) from supporting metrics
    const primaryMetricFound = metricsData.find((m) => m.name === metricType);
    
    // If metric wasn't found in computed data, use alert's baseline/recent values as fallback
    const primaryMetric = primaryMetricFound || {
      name: metricType,
      current_value: recentVal,
      baseline_value: baselineVal,
      percent_change: dev != null ? Math.round(dev * 100 * 10) / 10 : null,
      absolute_change: (recentVal != null && baselineVal != null) ? Math.round((recentVal - baselineVal) * 10) / 10 : null,
    };
    
    const supportingMetrics = metricsData.filter((m) => m.name !== metricType);

    // Map pillar from metric type
    const pillar = (() => {
      switch (metricType) {
        case "steps":
        case "movement_minutes": return "movement";
        case "sleep_minutes":
        case "sleep_efficiency_pct":
        case "deep_sleep_minutes": return "sleep";
        case "hrv_ms":
        case "resting_hr": return "stress";
        default: return "unknown";
      }
    })();

    // Calculate consecutive days from active_since to evaluated_end_date
    const activeSinceDate = new Date(`${alert.active_since ?? evaluatedEnd}T00:00:00Z`);
    const evaluatedEndDate = new Date(`${evaluatedEnd}T00:00:00Z`);
    const consecutiveDays = Math.max(1, Math.floor((evaluatedEndDate.getTime() - activeSinceDate.getTime()) / 86400000) + 1);

    const evidence: Record<string, unknown> = {
      alert: {
        metric: metricType,
        pattern: patternType,
        pillar,
        level,
        consecutive_days: consecutiveDays,
      },
      person: {
        name: memberFirst,
      },
      primary_metric: primaryMetric,
      supporting_metrics: supportingMetrics,
      context: {
        alert_start_date: alert.active_since ?? null,
        analysis_date: evaluatedEnd,
      },
      // Legacy fields for backwards compatibility
      severity: sev,
      window_days: 21,
      days_present: daysPresent,
      days_missing: missingDays,
    };

    console.log("📊 MIYA_INSIGHT: Evidence prepared", {
      alertStateId,
      metricType,
      level,
      consecutiveDays,
      primaryMetric: primaryMetric?.name,
      supportingMetrics: supportingMetrics.map(m => m.name),
      daysPresent,
    });

    if (logPayloads) console.log("MIYA_AI_EVIDENCE", evidence);

    // If AI disabled, return deterministic template + message suggestions.
    if (!enabled) {
      const msg = buildMessageSuggestions({ memberFirstName: memberFirst, metric: metricType, level, severity: sev });
      const pm = primaryMetric as any;
      const pctChange = pm?.percent_change ?? 0;
      const baselineValue = pm?.baseline_value ?? 0;
      const currentValue = pm?.current_value ?? 0;
      
      const clinicalInterpretation = pctChange !== 0
        ? `A ${Math.abs(pctChange).toFixed(1)}% change in ${metricDisplay(metricType).toLowerCase()} over ${level} days is notable. ${metricDisplay(metricType)} has shifted from a baseline of ${Math.round(baselineValue)} to ${Math.round(currentValue)}.`
        : `${metricDisplay(metricType)} is ${verb.verb} ${memberFirst}'s baseline over the last ${level} days.`;
      
      const resp: InsightResponse = {
        headline: `${metricDisplay(metricType)} ${verb.verb}`,
        clinical_interpretation: clinicalInterpretation,
        data_connections: `Based on ${daysPresent} days of data over the monitoring period.`,
        possible_causes: [],
        action_steps: [],
        message_suggestions: msg,
        confidence: daysPresent >= 18 ? "high" : daysPresent >= 12 ? "medium" : "low",
        confidence_reason: `Data coverage: ${daysPresent}/21 days present.`,
        evidence,
      };
      return jsonResponse({ ok: true, cached: false, model: "deterministic", ...resp });
    }

    const openaiKey = requireEnv("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL_INSIGHT") ?? "gpt-4o"; // Use best model for insight generation

    console.log("🤖 MIYA_INSIGHT: Calling OpenAI", { model, alertStateId, metricType });

    let ai: Omit<InsightResponse, "evidence">;
    try {
      ai = await callOpenAI({ apiKey: openaiKey, model, evidence });
      console.log("✅ MIYA_INSIGHT: OpenAI call succeeded", {
        headline: ai.headline,
        hasInterpretation: !!ai.clinical_interpretation,
        hasConnections: !!ai.data_connections,
        causesCount: ai.possible_causes?.length || 0,
        actionsCount: ai.action_steps?.length || 0,
      });
    } catch (aiError) {
      console.error("❌ MIYA_AI_CALL_FAILED", {
        error: String(aiError),
        stack: (aiError as Error).stack,
        alertStateId,
        metricType,
        level,
      });
      // Return deterministic fallback if AI fails
      const msg = buildMessageSuggestions({ memberFirstName: memberFirst, metric: metricType, level, severity: sev });
      const pm = primaryMetric as any;
      const pctChange = pm?.percent_change ?? 0;
      const baselineValue = pm?.baseline_value ?? 0;
      const currentValue = pm?.current_value ?? 0;
      
      const resp: InsightResponse = {
        headline: `${metricDisplay(metricType)} ${verb.verb}`,
        clinical_interpretation: `A ${Math.abs(pctChange).toFixed(1)}% change in ${metricDisplay(metricType).toLowerCase()} over ${level} days. ${metricDisplay(metricType)} has shifted from ${Math.round(baselineValue)} to ${Math.round(currentValue)}.`,
        data_connections: `Based on ${daysPresent} days of data over the monitoring period.`,
        possible_causes: [],
        action_steps: [],
        message_suggestions: msg,
        confidence: daysPresent >= 18 ? "high" : daysPresent >= 12 ? "medium" : "low",
        confidence_reason: `Data coverage: ${daysPresent}/21 days present. AI generation failed: ${String(aiError).substring(0, 100)}`,
        evidence,
      };
      return jsonResponse({ ok: true, cached: false, model: "fallback", ...resp });
    }
    
    const merged: InsightResponse = { ...ai, evidence };

    // If model forgot message suggestions, fill deterministic ones.
    if (!merged.message_suggestions?.length) {
      merged.message_suggestions = buildMessageSuggestions({ memberFirstName: memberFirst, metric: metricType, level, severity: sev });
    }

    console.log("💾 MIYA_INSIGHT: Saving to database", { alertStateId, promptVersion });

    // Summary is required by legacy schema; derive a safe fallback.
    const summary =
      merged.clinical_interpretation?.trim() ||
      merged.data_connections?.trim() ||
      merged.headline?.trim() ||
      "Insight generated.";

    const { error: insertErr } = await supabaseAdmin.from("pattern_alert_ai_insights").insert({
      alert_state_id: alertStateId,
      evaluated_end_date: evaluatedEnd,
      prompt_version: promptVersion,
      model,
      headline: merged.headline,
      summary,
      contributors: merged.possible_causes ?? [],
      actions: merged.action_steps ?? [],
      clinical_interpretation: merged.clinical_interpretation,
      data_connections: merged.data_connections,
      possible_causes: merged.possible_causes ?? [],
      action_steps: merged.action_steps ?? [],
      message_suggestions: merged.message_suggestions ?? [],
      confidence: merged.confidence ?? "medium",
      confidence_reason: merged.confidence_reason ?? "",
      evidence,
    });

    if (insertErr) {
      console.error("❌ MIYA_INSIGHT: Insert failed", insertErr);
      return jsonResponse({ ok: false, error: "Failed to save insight" }, 500);
    }

    console.log("✅ MIYA_INSIGHT: Returning final response", {
      alertStateId,
      headline: merged.headline?.substring(0, 50),
      hasInterpretation: !!merged.clinical_interpretation,
    });

    return jsonResponse({ ok: true, cached: false, model, ...merged });
  } catch (e) {
    console.error("❌ MIYA_INSIGHT_ERROR", {
      error: String(e),
      stack: (e as Error).stack,
      message: (e as Error).message,
    });
    return jsonResponse({ ok: false, error: String(e) }, 500);
  }
});

