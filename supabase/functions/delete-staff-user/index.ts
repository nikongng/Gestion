import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-user-access-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
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
    if (req.method !== "POST") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: corsHeaders,
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !serviceKey || !anonKey) {
      return jsonResponse(
        {
          error:
            "Secrets Supabase manquants dans la fonction delete-staff-user.",
        },
        500,
      );
    }

    const accessToken =
      req.headers.get("x-user-access-token")?.trim() ??
      req.headers.get("Authorization")?.replace("Bearer ", "").trim() ??
      "";
    if (!accessToken) {
      return jsonResponse({ error: "Non autorise" }, 401);
    }

    const userClient = createClient(supabaseUrl, anonKey);
    const {
      data: { user },
      error: userErr,
    } = await userClient.auth.getUser(accessToken);
    if (userErr || !user) {
      return jsonResponse({ error: "Session invalide" }, 401);
    }

    const adminClient = createClient(supabaseUrl, serviceKey);
    const { data: adminProfile, error: adminErr } = await adminClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (adminErr || adminProfile?.role !== "admin_provincial") {
      return jsonResponse(
        { error: "Suppression reservee a l'admin provincial." },
        403,
      );
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "JSON invalide" }, 400);
    }

    const userId = String(body.user_id ?? "").trim();
    if (!userId) {
      return jsonResponse({ error: "user_id requis" }, 400);
    }

    if (userId === user.id) {
      return jsonResponse(
        { error: "Impossible de supprimer votre propre compte." },
        400,
      );
    }

    const { data: targetProfile, error: targetErr } = await adminClient
      .from("profiles")
      .select("id, full_name, role")
      .eq("id", userId)
      .single();

    if (targetErr || !targetProfile) {
      return jsonResponse({ error: "Utilisateur introuvable." }, 404);
    }

    if (targetProfile.role === "admin_provincial") {
      return jsonResponse(
        { error: "Le compte admin provincial ne peut pas etre supprime." },
        403,
      );
    }

    const { error: deleteErr } = await adminClient.auth.admin.deleteUser(userId);
    if (deleteErr) {
      return jsonResponse({ error: deleteErr.message }, 500);
    }

    return jsonResponse({
      deleted_user_id: userId,
      full_name: targetProfile.full_name,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Erreur interne inattendue";
    return jsonResponse({ error: message }, 500);
  }
});
