import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

type FamilySnapshot = {
  sleep?: { status?: string; trend?: string; note?: string };
  movement?: { status?: string; trend?: string; note?: string };
  recovery?: { status?: string; trend?: string; note?: string };
  priority?: "sleep" | "movement" | "recovery" | string;
  summary?: string;
};

function normaliseLabel(input: string): string {
  const v = (input || "").trim().toLowerCase();
  if (!v) return "";
  if (["excellent", "great"].includes(v)) return "Excellent";
  if (["good"].includes(v)) return "Good";
  if (["ok", "okay"].includes(v)) return "Okay";
  if (["could be improved", "needs work", "poor", "bad"].includes(v))
    return "Could be improved";
  return input.trim();
}

// Trend wording that reads naturally alongside a status label.
function normaliseTrendHuman(input: string): string {
  const v = (input || "").trim().toLowerCase();
  if (!v) return "";
  if (["improving", "up", "better"].includes(v)) return "improving";
  if (["stable", "flat", "same"].includes(v)) return "steady";
  if (["declining", "down", "worse"].includes(v)) return "slipping";
  return v;
}

// Label relative to target (no invented 0-100 thresholds)
function labelFromTarget(current: number | null, target: number | null): string {
  if (current == null || target == null || target <= 0) return "Unknown";
  const ratio = current / target;
  if (ratio >= 1.0) return "Excellent";
  if (ratio >= 0.85) return "Good";
  if (ratio >= 0.7) return "Okay";
  return "Could be improved";
}

// Very simple trend from last-vs-prev.
// We keep the numeric delta internal; model sees only improving/steady/slipping.
function trendFromDelta(delta: number | null): string {
  if (delta === null || Number.isNaN(delta)) return "steady";
  if (delta >= 1) return "improving";
  if (delta <= -1) return "slipping";
  return "steady";
}

function buildFamilySnapshotMessage(snapshot: FamilySnapshot | null): ChatMessage | null {
  if (!snapshot) return null;

  const s = snapshot.sleep ?? {};
  const m = snapshot.movement ?? {};
  const r = snapshot.recovery ?? {};

  const sleepStatus = normaliseLabel(String(s.status ?? ""));
  const moveStatus = normaliseLabel(String(m.status ?? ""));
  const recStatus = normaliseLabel(String(r.status ?? ""));

  const sleepTrend = normaliseTrendHuman(String(s.trend ?? ""));
  const moveTrend = normaliseTrendHuman(String(m.trend ?? ""));
  const recTrend = normaliseTrendHuman(String(r.trend ?? ""));

  const priority = String(snapshot.priority ?? "").trim().toLowerCase();
  const priorityLine = priority ? `Priority focus: ${priority}.` : `Priority focus: unknown.`;

  const lines: string[] = [];
  lines.push("Family Snapshot (use this to answer specifically; do not invent data):");

  lines.push(
    `Sleep: ${sleepStatus || "Unknown"}${sleepTrend ? ` (${sleepTrend})` : ""}${
      s.note ? ` — ${String(s.note).trim()}` : ""
    }.`,
  );

  lines.push(
    `Movement: ${moveStatus || "Unknown"}${moveTrend ? ` (${moveTrend})` : ""}${
      m.note ? ` — ${String(m.note).trim()}` : ""
    }.`,
  );

  lines.push(
    `Recovery: ${recStatus || "Unknown"}${recTrend ? ` (${recTrend})` : ""}${
      r.note ? ` — ${String(r.note).trim()}` : ""
    }.`,
  );

  if (snapshot.summary && String(snapshot.summary).trim()) {
    lines.push(`Overall summary: ${String(snapshot.summary).trim()}`);
  }

  lines.push(priorityLine);

  return { role: "system", content: lines.join("\n") };
}

async function fetchFamilySnapshotFromSupabase(opts: {
  supabaseUrl: string;
  serviceRoleKey: string;
  jwt: string;
}): Promise<FamilySnapshot | null> {
  const { supabaseUrl, serviceRoleKey, jwt } = opts;

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  // Identify authed user
  const { data: userRes, error: userErr } = await supabase.auth.getUser(jwt);
  const authedUserId = userRes?.user?.id ?? null;

  if (userErr || !authedUserId) {
    console.log("arlo-chat: auth.getUser failed", userErr?.message ?? "no user");
    return null;
  }

  // Resolve family_id
  const { data: famRow, error: famErr } = await supabase
    .from("family_members")
    .select("family_id")
    .eq("user_id", authedUserId)
    .maybeSingle();

  if (famErr || !famRow?.family_id) {
    console.log("arlo-chat: family lookup failed", famErr?.message ?? "no family_id");
    return null;
  }

  const familyId = String(famRow.family_id);

  // Fetch all member user_ids in family
  const { data: members, error: memErr } = await supabase
    .from("family_members")
    .select("user_id")
    .eq("family_id", familyId);

  if (memErr || !members?.length) {
    console.log("arlo-chat: family members fetch failed", memErr?.message ?? "no members");
    return null;
  }

  const memberIds = members.map((m) => m.user_id).filter(Boolean).map(String);

  // Pull profiles (current snapshot) - ONLY what we need
  const { data: profiles, error: profErr } = await supabase
    .from("user_profiles")
    .select("user_id, first_name, vitality_score_current, optimal_vitality_target")
    .in("user_id", memberIds);

  if (profErr) console.log("arlo-chat: profiles fetch error", profErr.message);

  // Pull last 2 vitality_scores per member (for trend)
  const { data: vs, error: vsErr } = await supabase
    .from("vitality_scores")
    .select("user_id, score_date, total_score")
    .in("user_id", memberIds)
    .order("score_date", { ascending: false })
    .limit(Math.min(200, memberIds.length * 4)); // cap

  if (vsErr) console.log("arlo-chat: vitality_scores fetch error", vsErr.message);

  // Helpers
  const profileByUser = new Map<string, any>();
  (profiles ?? []).forEach((p: any) => profileByUser.set(String(p.user_id), p));

  const vsByUser = new Map<string, any[]>();
  (vs ?? []).forEach((row: any) => {
    const k = String(row.user_id);
    const arr = vsByUser.get(k) ?? [];
    arr.push(row);
    vsByUser.set(k, arr);
  });

  // Family aggregation: we keep it simple and honest.
  // - Status: worst (lowest) across members (so you focus where it matters)
  // - Trend: if any slipping -> slipping; else if any improving -> improving; else steady
  const statusRank: Record<string, number> = {
    Unknown: 0,
    Excellent: 4,
    Good: 3,
    Okay: 2,
    "Could be improved": 1,
  };

  let familyStatus = "Unknown";
  let familyTrend: "improving" | "steady" | "slipping" = "steady";

  const memberSummaries: string[] = [];

  for (const uid of memberIds) {
    const p = profileByUser.get(uid);
    const current = typeof p?.vitality_score_current === "number" ? p.vitality_score_current : null;
    const target = typeof p?.optimal_vitality_target === "number" ? p.optimal_vitality_target : null;

    const memberStatus = labelFromTarget(current, target);

    const rows = (vsByUser.get(uid) ?? []).slice(0, 2);
    const latest = typeof rows[0]?.total_score === "number" ? rows[0].total_score : null;
    const prev = typeof rows[1]?.total_score === "number" ? rows[1].total_score : null;
    const delta = latest != null && prev != null ? latest - prev : null;

    const memberTrend = trendFromDelta(delta) as "improving" | "steady" | "slipping";

    // Update family status (lowest wins), but don't let Unknown override known values
    if (memberStatus !== "Unknown") {
      if (familyStatus === "Unknown") familyStatus = memberStatus;
      else if ((statusRank[memberStatus] ?? 0) < (statusRank[familyStatus] ?? 0)) familyStatus = memberStatus;
    }

    // Update family trend
    if (memberTrend === "slipping") familyTrend = "slipping";
    else if (familyTrend !== "slipping" && memberTrend === "improving") familyTrend = "improving";

    const name = String(p?.first_name ?? "").trim();
    // No numbers in the notes. Just a lightweight human summary.
    memberSummaries.push(`${name || "Member"}: ${memberStatus} (${memberTrend})`);
  }

  // Priority logic (simple and readable)
  let priority: "sleep" | "movement" | "recovery" = "movement";
  if (familyTrend === "slipping" || familyStatus === "Could be improved") priority = "recovery";
  else if (familyStatus === "Okay") priority = "sleep";

  const summary = `Overall: ${familyStatus} (${familyTrend}).`;

  // Until you define real pillar mappings, don't pretend.
  // We provide a family-level snapshot used to answer conversations.
  return {
    sleep: { status: familyStatus, trend: familyTrend, note: memberSummaries.slice(0, 4).join(" | ") },
    movement: { status: familyStatus, trend: familyTrend, note: memberSummaries.slice(0, 4).join(" | ") },
    recovery: { status: familyStatus, trend: familyTrend, note: memberSummaries.slice(0, 4).join(" | ") },
    priority,
    summary,
  };
}

function safeJsonHeaders(extra: Record<string, string> = {}) {
  return { ...corsHeaders, "Content-Type": "application/json", ...extra };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Use POST" }), {
      status: 405,
      headers: safeJsonHeaders(),
    });
  }

  const t0 = Date.now();
  console.log("arlo-chat: start");

  try {
    const body = await req.json().catch(() => null);

    const messages = (body?.messages ?? []) as ChatMessage[];
    const firstName = String(body?.firstName ?? "");
    const openingLine = String(body?.openingLine ?? "");

    if (!Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: "Missing `messages` array." }), {
        status: 400,
        headers: safeJsonHeaders(),
      });
    }

    for (const m of messages) {
      if (
        !m ||
        (m.role !== "system" && m.role !== "user" && m.role !== "assistant") ||
        typeof m.content !== "string"
      ) {
        return new Response(JSON.stringify({ error: "Invalid message format." }), {
          status: 400,
          headers: safeJsonHeaders(),
        });
      }
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    const model = Deno.env.get("OPENAI_MODEL") ?? "gpt-4o-mini";

    if (!apiKey) {
      return new Response(JSON.stringify({ error: "Missing OPENAI_API_KEY secret." }), {
        status: 500,
        headers: safeJsonHeaders(),
      });
    }

    // Supabase secrets (must be set in Edge Function secrets)
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    // JWT from client request
    const authHeader = req.headers.get("authorization") ?? req.headers.get("Authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

    // 1) Fetch snapshot (fast + capped)
    let familySnapshot: FamilySnapshot | null = null;
    if (supabaseUrl && serviceRoleKey && jwt) {
      const ts0 = Date.now();
      console.log("arlo-chat: fetching family snapshot");
      familySnapshot = await fetchFamilySnapshotFromSupabase({ supabaseUrl, serviceRoleKey, jwt });
      console.log(
        "arlo-chat: snapshot present",
        !!familySnapshot,
        "ms",
        Date.now() - ts0,
      );
    } else {
      console.log("arlo-chat: missing SUPABASE_URL / SERVICE_ROLE / JWT; skipping snapshot");
    }

    // 2) Build system prompt: Miya, warm, one question only, no repetitive offers
    const system: ChatMessage = {
      role: "system",
      content: `
You are Miya: a warm, supportive family health and wellness coach (British English). Sound natural, informative, warm, and motivating—like a trusted friend who cares about the family. Your job is to answer the user's question clearly, using the Family Snapshot when present.

Rules:
- You MAY reference OVERVIEWS and TRENDS only (Excellent/Good/Okay/Could be improved + improving/steady/slipping). Do NOT show raw numbers unless the user explicitly asks.
- Do NOT diagnose medical conditions.
- When you want to learn more, end your message with exactly ONE question. Never ask two or more questions in one reply—the only question should be the last sentence.
- Avoid repeating the same phrases or offers every message (e.g. "7-day plan", "deeper dive", "quick tip"). Vary your language and keep the conversation fresh and natural.
- If the Family Snapshot includes per-member summaries, you MUST compare members when the user asks "who", "which", or "most". Never say you cannot tell if member-level summaries are present.

Reply style:
- Give a direct, warm answer first (1–2 sentences).
- Briefly tie to the snapshot or their message when relevant ("Why" in one short line).
- Suggest one simple next step the whole family can do in 24h when it fits.
- End with exactly one question if you want to learn more—nothing else after that question.

Keep it conversational. 80–140 words.
      `.trim(),
    };

    const contextBits: string[] = [];
    if (firstName.trim()) contextBits.push(`User first name: ${firstName.trim()}.`);
    if (openingLine.trim()) contextBits.push(`Opening context: ${openingLine.trim()}.`);

    const contextSystem: ChatMessage | null = contextBits.length
      ? { role: "system", content: contextBits.join(" ") }
      : null;

    const snapshotSystem = buildFamilySnapshotMessage(familySnapshot);

    // Keep only last N messages for speed and relevance
    const recentMessages = messages
      .filter((m) => typeof m.content === "string" && m.content.trim().length > 0)
      .slice(-10);

    const input: ChatMessage[] = [
      system,
      ...(snapshotSystem ? [snapshotSystem] : []),
      ...(contextSystem ? [contextSystem] : []),
      ...recentMessages,
    ];

    // 3) OpenAI call with robust timeout handling
    const payload = {
      model,
      input,
      max_output_tokens: 260,
    };

    console.log("arlo-chat: calling openai", { model, inputCount: input.length });

    const controller = new AbortController();
    const timeoutMs = 45000;
    const timeout = setTimeout(() => controller.abort(), timeoutMs);

    let resp: Response;
    try {
      resp = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
        signal: controller.signal,
      });
    } catch (err) {
      const msg = String(err);
      const isAbort =
        msg.toLowerCase().includes("abort") || msg.toLowerCase().includes("aborted");

      console.log("arlo-chat: openai fetch threw", msg);

      return new Response(
        JSON.stringify({
          reply: isAbort
            ? "Sorry — that took too long. Would you like a quick family overview, or shall we focus on sleep, movement, or recovery first?"
            : "Sorry — I couldn’t reach the coach right now. Try again in a moment.",
        }),
        { status: 200, headers: safeJsonHeaders() },
      );
    } finally {
      clearTimeout(timeout);
    }

    console.log("arlo-chat: openai returned", resp.status, "ms", Date.now() - t0);

    let data: any = null;
    try {
      data = await resp.json();
    } catch {
      const t = await resp.text().catch(() => "");
      data = { parse_error: true, status: resp.status, body: t };
    }

    if (!resp.ok) {
      console.log("arlo-chat: openai not ok", { status: resp.status, data });

      return new Response(
        JSON.stringify({
          reply:
            "I couldn’t generate that just now. Would you like a quick overview, or pick one to focus on: sleep, movement, or recovery?",
          status: resp.status,
        }),
        { status: 200, headers: safeJsonHeaders() },
      );
    }

    // Extract output text
    const outputText =
      data?.output_text ??
      data?.output?.find((o: any) => o?.type === "message")?.content
        ?.map((c: any) => c?.text ?? "")
        .join("") ??
      "";

    return new Response(
      JSON.stringify({
        reply: (outputText && String(outputText).trim()) || "Sorry — I couldn’t generate a reply.",
      }),
      { status: 200, headers: safeJsonHeaders() },
    );
  } catch (e) {
    console.log("arlo-chat: unhandled error", String(e));

    return new Response(
      JSON.stringify({
        reply:
          "Sorry — something went wrong on my side. Try again, or tell me if you’d like to focus on sleep, movement, or recovery first.",
        error: "Unhandled error",
      }),
      { status: 200, headers: safeJsonHeaders() },
    );
  }
});
