// DÃ©ployer : supabase functions deploy create-staff-user
// Secrets : SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY (auto)

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
            "Secrets Supabase manquants dans la fonction create-staff-user.",
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
    const { data: adminProfile, error: profErr } = await adminClient
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .single();

    if (profErr || adminProfile?.role !== "admin_provincial") {
      return jsonResponse(
        { error: "Reserve a l'admin provincial." },
        403,
      );
    }

    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "JSON invalide" }, 400);
    }

    const email = String(body.email ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const full_name = String(body.full_name ?? "").trim();
    const role = String(body.role ?? "");
    const commune_id =
      typeof body.commune_id === "string" ? body.commune_id : null;

    if (!email || !password || !full_name) {
      return jsonResponse(
        { error: "email, password et full_name requis" },
        400,
      );
    }

    if (password.length < 6) {
      return jsonResponse(
        { error: "Le mot de passe doit contenir au moins 6 caracteres." },
        400,
      );
    }

    const communeRoles = new Set([
      "bourgmestre",
      "agent",
      "taxateur",
      "ordonnateur",
      "apureur",
    ]);
    const allowedRoles = new Set([
      "bourgmestre",
      "agent",
      "taxateur",
      "ordonnateur",
      "apureur",
      "ministre_finances",
      "gouverneur",
    ]);

    if (!allowedRoles.has(role)) {
      return jsonResponse({ error: "Role invalide" }, 400);
    }

    if (communeRoles.has(role) && !commune_id) {
      return jsonResponse({ error: "commune_id requis pour ce role" }, 400);
    }

    const { data: created, error: createErr } =
      await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { full_name },
      });

    if (createErr) {
      return jsonResponse({ error: createErr.message }, 400);
    }

    const newId = created.user?.id;
    if (!newId) {
      return jsonResponse(
        {
          error:
            "Le compte Auth n'a pas renvoye d'identifiant. Verifiez la fonction.",
        },
        500,
      );
    }

    const { error: insErr } = await adminClient.from("profiles").insert({
      id: newId,
      full_name,
      role,
      commune_id,
    });

    if (insErr) {
      await adminClient.auth.admin.deleteUser(newId);
      return jsonResponse(
        {
          error: `Profil non cree : ${insErr.message}. Le compte Auth cree a ete annule.`,
        },
        500,
      );
    }

    return jsonResponse({ user_id: newId, email });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Erreur interne inattendue";
    return jsonResponse({ error: message }, 500);
  }
});


