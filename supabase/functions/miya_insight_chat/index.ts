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
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model,
      input: [{ role: "system", content: system }, ...messages],
    }),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`OpenAI error: ${res.status} ${txt}`);
  }
  const data = await res.json();
  const outText: string | undefined =
    data?.output?.[0]?.content?.find((c: any) => c?.type === "output_text")?.text ??
    data?.output_text ??
    undefined;
  if (!outText) throw new Error("OpenAI response missing output_text");
  return outText;
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

    const body = await req.json().catch(() => null) as { alert_state_id?: string; message?: string } | null;
    const alertStateId = body?.alert_state_id;
    const message = (body?.message ?? "").trim();
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
      .select("headline,summary,evidence")
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

    const system = [
      "You are Miya, a caring family-care health assistant.",
      "You answer questions about one specific insight. Keep answers concise and practical.",
      "You MUST use the provided evidence JSON. Do not invent numbers or new trends.",
      "No diagnosis and no medical claims. Encourage check-ins and low-risk actions.",
      "If asked for medical advice, recommend consulting a clinician.",
    ].join("\n");

    const context = `INSIGHT_HEADLINE: ${cached.headline}\nINSIGHT_SUMMARY: ${cached.summary}\nEVIDENCE_JSON:\n${JSON.stringify(cached.evidence)}\n`;

    const chatMessages: Array<{ role: "user" | "assistant"; content: string }> = [
      { role: "user", content: context },
      ...(msgs ?? []).map((m: any) => ({ role: m.role, content: m.content })),
    ];

    const openaiKey = requireEnv("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL_CHAT") ?? "gpt-4.1-mini";
    const reply = await callOpenAI({ apiKey: openaiKey, model, system, messages: chatMessages });

    await supabaseAdmin.from("pattern_alert_ai_messages").insert({ thread_id: threadId, role: "assistant", content: reply });

    return jsonResponse({ ok: true, reply });
  } catch (e) {
    console.error("MIYA_INSIGHT_CHAT_ERROR", String(e));
    return jsonResponse({ ok: false, error: String(e) }, 500);
  }
});

