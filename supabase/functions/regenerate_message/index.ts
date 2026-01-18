import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Auth check
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

    // Get request body
    const body = await req.json();
    const { original_message, tone, member_name } = body;

    if (!original_message || !tone) {
      return jsonResponse({ error: "Missing required fields" }, 400);
    }

    // Call OpenAI
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      throw new Error("OpenAI API key not configured");
    }

    const toneInstructions = {
      "Warm & caring": "Use warm, compassionate language. Show empathy and care. Make it feel like a close friend reaching out.",
      "Motivating": "Use energizing, motivating language. Be encouraging, positive, and inspiring. Focus on possibilities and progress.",
      "Direct & friendly": "Be direct and to-the-point while remaining friendly. No fluff. Clear and actionable but still warm."
    };

    const instruction = toneInstructions[tone as keyof typeof toneInstructions] || toneInstructions["Warm & caring"];

    const prompt = `Rewrite this outreach message in a "${tone}" tone. Keep it around the same length and preserve the core message.

Original message:
"${original_message}"

Guidelines:
- ${instruction}
- The message is about ${member_name}
- Keep it personal and natural
- Preserve any specific data or facts mentioned
- Don't change the core message, just adjust the tone and style

Rewritten message:`;

    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openaiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { 
            role: "system", 
            content: "You are a helpful writing assistant that rewrites health-related messages in different tones while preserving factual content." 
          },
          { role: "user", content: prompt }
        ],
        temperature: 0.7,
        max_tokens: 300
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`OpenAI error: ${response.status} ${errorText}`);
    }

    const data = await response.json();
    const message = data.choices?.[0]?.message?.content?.trim();

    if (!message) {
      throw new Error("No message generated");
    }

    return jsonResponse({ message });

  } catch (error) {
    console.error("Error:", error);
    return jsonResponse(
      { error: error instanceof Error ? error.message : "Internal error" },
      500
    );
  }
});
