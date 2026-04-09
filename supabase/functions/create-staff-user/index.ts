// DÃ©ployer : supabase functions deploy create-staff-user
// Secrets : SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY (auto)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: corsHeaders,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Non autorisÃ©" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userErr,
  } = await userClient.auth.getUser();
  if (userErr || !user) {
    return new Response(JSON.stringify({ error: "Session invalide" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const adminClient = createClient(supabaseUrl, serviceKey);
  const { data: adminProfile, error: profErr } = await adminClient
    .from("profiles")
    .select("role")
    .eq("id", user.id)
    .single();

  if (
    profErr ||
    !["admin_provincial", "ministre_finances", "gouverneur"].includes(
      adminProfile?.role ?? "",
    )
  ) {
    return new Response(JSON.stringify({ error: "RÃ©servÃ© Ã  lâ€™admin provincial" }), {
      status: 403,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "JSON invalide" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const email = String(body.email ?? "").trim();
  const password = String(body.password ?? "");
  const full_name = String(body.full_name ?? "").trim();
  const role = String(body.role ?? "");
  const commune_id =
    typeof body.commune_id === "string" ? body.commune_id : null;

  if (!email || !password || !full_name) {
    return new Response(
      JSON.stringify({ error: "email, password et full_name requis" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const communeRoles = new Set(["bourgmestre", "agent"]);
  const allowedRoles = new Set([
    "bourgmestre",
    "agent",
    "ministre_finances",
    "gouverneur",
  ]);

  if (!allowedRoles.has(role)) {
    return new Response(JSON.stringify({ error: "RÃ´le invalide" }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (communeRoles.has(role) && !commune_id) {
    return new Response(
      JSON.stringify({ error: "commune_id requis pour ce rÃ´le" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  const { data: created, error: createErr } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name },
  });

  if (createErr) {
    return new Response(JSON.stringify({ error: createErr.message }), {
      status: 400,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const newId = created.user!.id;
  const { error: insErr } = await adminClient.from("profiles").insert({
    id: newId,
    full_name,
    role,
    commune_id,
  });

  if (insErr) {
    return new Response(
      JSON.stringify({
        error: `Profil non crÃ©Ã© : ${insErr.message}. Compte auth peut exister : Ã  nettoyer manuellement.`,
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  return new Response(JSON.stringify({ user_id: newId, email }), {
    status: 200,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});


