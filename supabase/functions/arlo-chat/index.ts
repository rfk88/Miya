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

/** Shared calm fallback copy (aligned with other Miya edge functions). */
const FALLBACK_TIMEOUT =
  "Sorry — that took a bit too long. When you're ready, tell me whether you'd like a quick family overview or to focus on sleep, movement, or recovery first.";
const FALLBACK_NETWORK =
  "Sorry — I couldn't reach Miya just now. Please try again in a moment.";
const FALLBACK_OPENAI_ERROR =
  "I couldn't finish that reply just now. Would you like a quick overview, or shall we pick one area — sleep, movement, or recovery?";
const FALLBACK_UNHANDLED =
  "Sorry — something went wrong on my side. Please try again, or say whether you'd like to focus on sleep, movement, or recovery first.";
const FALLBACK_EMPTY_REPLY = "Sorry — I couldn't generate a reply. Please try again.";

/** If user text suggests an emergency, respond without calling the model. */
const EMERGENCY_REPLY =
  "If you or someone with you might be having a medical emergency — for example severe chest pain, trouble breathing, confusion, weakness on one side, severe bleeding, or thoughts of self-harm — please contact emergency services straight away (999 in the UK, 911 in the US) or go to A&E. I'm not able to help with emergencies here. Once everyone is safe, I'm here for everyday wellbeing questions about your family.";

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

function normaliseTrendHuman(input: string): string {
  const v = (input || "").trim().toLowerCase();
  if (!v) return "";
  if (["improving", "up", "better"].includes(v)) return "improving";
  if (["stable", "flat", "same"].includes(v)) return "steady";
  if (["declining", "down", "worse"].includes(v)) return "slipping";
  return v;
}

function labelFromTarget(current: number | null, target: number | null): string {
  if (current == null || target == null || target <= 0) return "Unknown";
  const ratio = current / target;
  if (ratio >= 1.0) return "Excellent";
  if (ratio >= 0.85) return "Good";
  if (ratio >= 0.7) return "Okay";
  return "Could be improved";
}

function trendFromDelta(delta: number | null): string {
  if (delta === null || Number.isNaN(delta)) return "steady";
  if (delta >= 1) return "improving";
  if (delta <= -1) return "slipping";
  return "steady";
}

/** Lightweight scan of recent user messages for possible emergency wording. */
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
  lines.push(
    "Family Snapshot (ground truth for this reply — use only what appears here; do not invent numbers or medical facts):",
  );

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

function buildDashboardContextMessage(raw: unknown): ChatMessage | null {
  if (!raw || typeof raw !== "object") return null;
  const ctx = raw as Record<string, any>;
  const lines: string[] = [
    "Current Dashboard Context (preferred source of truth for this reply; use this before any backend snapshot and do not invent missing health facts):",
  ];

  if (typeof ctx.familyScore === "number") {
    lines.push(`Family vitality score: ${Math.round(ctx.familyScore)}/100.`);
  }
  if (typeof ctx.familyScoreLabel === "string" && ctx.familyScoreLabel.trim()) {
    lines.push(`Family vitality label: ${ctx.familyScoreLabel.trim()}.`);
  }
  if (typeof ctx.dataFreshnessSummary === "string" && ctx.dataFreshnessSummary.trim()) {
    lines.push(`Data freshness: ${ctx.dataFreshnessSummary.trim()}`);
  }
  if (typeof ctx.memberCount === "number") {
    lines.push(`Members loaded: ${Math.round(ctx.memberCount)}.`);
  }

  if (Array.isArray(ctx.pillars) && ctx.pillars.length > 0) {
    lines.push("Pillars:");
    for (const p of ctx.pillars.slice(0, 6)) {
      if (!p || typeof p !== "object") continue;
      const name = String(p.name ?? "").trim() || "Unknown";
      const score = typeof p.score === "number" ? `${Math.round(p.score)}/100` : "unknown score";
      const label = String(p.label ?? "").trim() || "Unknown";
      lines.push(`- ${name}: ${score}, ${label}.`);
    }
  }

  if (Array.isArray(ctx.activeAlerts) && ctx.activeAlerts.length > 0) {
    lines.push("Active relevant alerts:");
    for (const alert of ctx.activeAlerts.slice(0, 5)) {
      if (!alert || typeof alert !== "object") continue;
      const memberName = String(alert.memberName ?? "").trim() || "A family member";
      const pillar = String(alert.pillar ?? "").trim() || "a pillar";
      const days =
        typeof alert.durationDays === "number"
          ? ` for ${Math.round(alert.durationDays)} days`
          : "";
      lines.push(`- ${memberName}: ${pillar}${days}.`);
    }
  } else {
    lines.push("Active relevant alerts: none.");
  }

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

  const { data: userRes, error: userErr } = await supabase.auth.getUser(jwt);
  const authedUserId = userRes?.user?.id ?? null;

  if (userErr || !authedUserId) {
    console.log("arlo-chat: auth.getUser failed", userErr?.message ?? "no user");
    return null;
  }

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

  const { data: members, error: memErr } = await supabase
    .from("family_members")
    .select("user_id")
    .eq("family_id", familyId);

  if (memErr || !members?.length) {
    console.log("arlo-chat: family members fetch failed", memErr?.message ?? "no members");
    return null;
  }

  const memberIds = members.map((m) => m.user_id).filter(Boolean).map(String);

  const { data: profiles, error: profErr } = await supabase
    .from("user_profiles")
    .select("user_id, first_name, vitality_score_current, optimal_vitality_target")
    .in("user_id", memberIds);

  if (profErr) console.log("arlo-chat: profiles fetch error", profErr.message);

  const { data: vs, error: vsErr } = await supabase
    .from("vitality_scores")
    .select("user_id, score_date, total_score")
    .in("user_id", memberIds)
    .order("score_date", { ascending: false })
    .limit(Math.min(200, memberIds.length * 4));

  if (vsErr) console.log("arlo-chat: vitality_scores fetch error", vsErr.message);

  const profileByUser = new Map<string, any>();
  (profiles ?? []).forEach((p: any) => profileByUser.set(String(p.user_id), p));

  const vsByUser = new Map<string, any[]>();
  (vs ?? []).forEach((row: any) => {
    const k = String(row.user_id);
    const arr = vsByUser.get(k) ?? [];
    arr.push(row);
    vsByUser.set(k, arr);
  });

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

    if (memberStatus !== "Unknown") {
      if (familyStatus === "Unknown") familyStatus = memberStatus;
      else if ((statusRank[memberStatus] ?? 0) < (statusRank[familyStatus] ?? 0)) familyStatus = memberStatus;
    }

    if (memberTrend === "slipping") familyTrend = "slipping";
    else if (familyTrend !== "slipping" && memberTrend === "improving") familyTrend = "improving";

    const name = String(p?.first_name ?? "").trim();
    memberSummaries.push(`${name || "Member"}: ${memberStatus} (${memberTrend})`);
  }

  let priority: "sleep" | "movement" | "recovery" = "movement";
  if (familyTrend === "slipping" || familyStatus === "Could be improved") priority = "recovery";
  else if (familyStatus === "Okay") priority = "sleep";

  const summary = `Overall: ${familyStatus} (${familyTrend}).`;

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

function buildMiyaFamilySystemPrompt(): string {
  return `
You are Miya: a warm, trustworthy family wellbeing coach (British English). You help households think clearly about sleep, movement, and recovery — not as a doctor, but as a calm, informed companion.

TRUST CONTRACT (always follow):
1) Acknowledge the human concern first in plain language when the user sounds worried or frustrated (one short sentence).
2) Say what you can see from the Current Dashboard Context or Family Snapshot when present. If the available context is missing or thin, say clearly that your view is limited and avoid guessing.
3) Never invent raw numbers, lab results, diagnoses, or medical certainty. Do not diagnose conditions or imply you examined someone.
4) You MAY use overview labels, pillar states, and trends from the current context: Excellent / Good / Okay / Could be improved, and improving / steady / slipping. Do not show raw scores unless the user explicitly asks for numbers.
5) If the user asks "who", "which", or "most" and per-member or active-alert lines appear in the current context, compare members fairly and specifically. If those lines are absent, say you don't have member-level detail in what you can see.
6) Offer one realistic next step the family could try in the next 24 hours when it fits — small, kind, and specific.
7) If you need to learn more, end with at most ONE question, as the last sentence. Do not ask two questions in one reply.
8) Vary your wording; avoid repeating the same stock phrases every turn (e.g. "7-day plan", "deep dive") unless the user asks.

SAFETY:
- If the user describes possible emergency symptoms (severe chest pain, trouble breathing, stroke signs, severe bleeding, thoughts of self-harm), do not coach: give a brief urgent-care directive and stop. (The system may also intercept these messages.)

LENGTH: About 80–140 words. Sound natural — like a trusted friend who respects boundaries.
`.trim();
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
    const dashboardContext = body?.dashboardContext ?? null;

    if (!Array.isArray(messages) || messages.length === 0) {
      return new Response(JSON.stringify({ error: "Missing messages array." }), {
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

    const recentUserTexts = messages
      .filter((m) => m.role === "user")
      .map((m) => m.content)
      .slice(-5);
    if (looksLikeUrgentMedicalOrCrisis(recentUserTexts)) {
      console.log("arlo-chat: urgent/crisis pattern — skipping model");
      return new Response(JSON.stringify({ reply: EMERGENCY_REPLY }), {
        status: 200,
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const authHeader = req.headers.get("authorization") ?? req.headers.get("Authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

    if (!supabaseUrl || !serviceRoleKey || !jwt) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: safeJsonHeaders(),
      });
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);
    const { data: authUser, error: authErr } = await supabaseAdmin.auth.getUser(jwt);
    if (authErr || !authUser?.user?.id) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: safeJsonHeaders(),
      });
    }
    const consentOk = await isAIThirdPartySharingEnabledForUser(supabaseAdmin, authUser.user.id);
    if (!consentOk) {
      console.log("arlo-chat: third-party AI consent denied for user", authUser.user.id);
      return new Response(JSON.stringify(AI_CONSENT_DENIED_JSON), {
        status: 403,
        headers: safeJsonHeaders(),
      });
    }

    const dashboardContextSystem = buildDashboardContextMessage(dashboardContext);

    let familySnapshot: FamilySnapshot | null = null;
    if (!dashboardContextSystem) {
      const ts0 = Date.now();
      console.log("arlo-chat: fetching family snapshot");
      familySnapshot = await fetchFamilySnapshotFromSupabase({ supabaseUrl, serviceRoleKey, jwt });
      console.log("arlo-chat: snapshot present", !!familySnapshot, "ms", Date.now() - ts0);
    } else {
      console.log("arlo-chat: using client dashboard context");
    }

    const system: ChatMessage = {
      role: "system",
      content: buildMiyaFamilySystemPrompt(),
    };

    const contextBits: string[] = [];
    if (firstName.trim()) contextBits.push(`User first name: ${firstName.trim()}.`);
    if (openingLine.trim()) contextBits.push(`Opening context from the app: ${openingLine.trim()}.`);
    if (dashboardContextSystem) {
      contextBits.push(
        "Use the Current Dashboard Context as the most current truth. If it says there are no active relevant alerts, do not imply a current warning.",
      );
    }
    if (!dashboardContextSystem && !familySnapshot) {
      contextBits.push(
        "No Family Snapshot is available for this reply — say so briefly and avoid fabricating family metrics.",
      );
    }

    const contextSystem: ChatMessage | null = contextBits.length
      ? { role: "system", content: contextBits.join(" ") }
      : null;

    const snapshotSystem = buildFamilySnapshotMessage(familySnapshot);

    const recentMessages = messages
      .filter((m) => typeof m.content === "string" && m.content.trim().length > 0)
      .slice(-10);

    const input: ChatMessage[] = [
      system,
      ...(dashboardContextSystem ? [dashboardContextSystem] : []),
      ...(snapshotSystem ? [snapshotSystem] : []),
      ...(contextSystem ? [contextSystem] : []),
      ...recentMessages,
    ];

    const payload = {
      model,
      messages: input,
      max_tokens: 280,
    };

    console.log("arlo-chat: calling openai", { model, inputCount: input.length });

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
          reply: isAbort ? FALLBACK_TIMEOUT : FALLBACK_NETWORK,
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
          reply: FALLBACK_OPENAI_ERROR,
          status: resp.status,
        }),
        { status: 200, headers: safeJsonHeaders() },
      );
    }

    const outputText = data?.choices?.[0]?.message?.content ?? "";
    const trimmed = outputText && String(outputText).trim();

    return new Response(
      JSON.stringify({
        reply: trimmed || FALLBACK_EMPTY_REPLY,
      }),
      { status: 200, headers: safeJsonHeaders() },
    );
  } catch (e) {
    console.log("arlo-chat: unhandled error", String(e));

    return new Response(
      JSON.stringify({
        reply: FALLBACK_UNHANDLED,
        error: "Unhandled error",
      }),
      { status: 200, headers: safeJsonHeaders() },
    );
  }
});
