import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

type PermanentDeletionResponse = {
  success: boolean;
  stage:
    | "unauthorized"
    | "family_cleanup_failed"
    | "family_cleanup_complete"
    | "already_not_in_family_or_member_cleanup_complete"
    | "auth_delete_failed"
    | "auth_delete_complete";
  message: string;
  requires_admin_cleanup: boolean;
  family_result?: Record<string, unknown> | null;
};

type RpcResponse = {
  success?: boolean;
  stage?: string;
  message?: string;
  requires_admin_cleanup?: boolean;
  family_result?: Record<string, unknown> | null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ success: false, error: "Use POST" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse(
      {
        success: false,
        stage: "auth_delete_failed",
        message: "Supabase environment is not configured correctly.",
        requires_admin_cleanup: true,
      } satisfies PermanentDeletionResponse,
      500,
    );
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
  if (!token) {
    return jsonResponse(
      {
        success: false,
        stage: "unauthorized",
        message: "Unauthorized",
        requires_admin_cleanup: false,
      } satisfies PermanentDeletionResponse,
      401,
    );
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${token}` } },
  });
  const serviceClient = createClient(supabaseUrl, serviceRoleKey);

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData?.user?.id) {
    return jsonResponse(
      {
        success: false,
        stage: "unauthorized",
        message: "Unauthorized",
        requires_admin_cleanup: false,
      } satisfies PermanentDeletionResponse,
      401,
    );
  }

  const userId = userData.user.id;

  const { data: rpcData, error: rpcErr } = await userClient.rpc("delete_my_account_permanently");
  if (rpcErr) {
    return jsonResponse(
      {
        success: false,
        stage: "family_cleanup_failed",
        message: rpcErr.message,
        requires_admin_cleanup: false,
      } satisfies PermanentDeletionResponse,
      500,
    );
  }

  const rpc = (rpcData ?? {}) as RpcResponse;
  if (!rpc.success) {
    return jsonResponse(
      {
        success: false,
        stage: "family_cleanup_failed",
        message: rpc.message ?? "Account cleanup failed.",
        requires_admin_cleanup: Boolean(rpc.requires_admin_cleanup),
        family_result: rpc.family_result ?? null,
      } satisfies PermanentDeletionResponse,
      500,
    );
  }

  const { error: deleteErr } = await serviceClient.auth.admin.deleteUser(userId);
  if (deleteErr) {
    const msg = deleteErr.message?.toLowerCase() ?? "";
    const alreadyDeleted = msg.includes("not found") || msg.includes("user not found");
    if (!alreadyDeleted) {
      return jsonResponse(
        {
          success: false,
          stage: "auth_delete_failed",
          message: deleteErr.message,
          requires_admin_cleanup: true,
          family_result: rpc.family_result ?? null,
        } satisfies PermanentDeletionResponse,
        500,
      );
    }
  }

  return jsonResponse(
    {
      success: true,
      stage: "auth_delete_complete",
      message: "Account deleted permanently.",
      requires_admin_cleanup: false,
      family_result: rpc.family_result ?? null,
    } satisfies PermanentDeletionResponse,
    200,
  );
});
