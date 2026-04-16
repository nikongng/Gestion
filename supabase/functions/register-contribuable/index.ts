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

async function generateTaxpayerIdentifier(
  adminClient: ReturnType<typeof createClient>,
) {
  const year = new Date().getFullYear();

  for (let attempt = 0; attempt < 12; attempt++) {
    const random = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
    const identifier = `CTR-${year}-${String(random).padStart(6, "0")}`;

    const { data, error } = await adminClient
      .from("profiles")
      .select("id")
      .eq("taxpayer_identifier", identifier)
      .maybeSingle();

    if (error) {
      throw error;
    }
    if (!data) {
      return identifier;
    }
  }

  throw new Error(
    "Impossible de generer un identifiant contribuable unique.",
  );
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
    if (!supabaseUrl || !serviceKey) {
      return jsonResponse(
        {
          error:
            "Secrets Supabase manquants dans la fonction register-contribuable.",
        },
        500,
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
    const fullName = String(body.full_name ?? "").trim();

    if (!email || !password || !fullName) {
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

    const adminClient = createClient(supabaseUrl, serviceKey);
    const taxpayerIdentifier = await generateTaxpayerIdentifier(adminClient);

    const { data: created, error: createErr } =
      await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: {
          full_name: fullName,
          role: "contribuable",
          taxpayer_identifier: taxpayerIdentifier,
        },
      });

    if (createErr) {
      return jsonResponse({ error: createErr.message }, 400);
    }

    const userId = created.user?.id;
    if (!userId) {
      return jsonResponse(
        {
          error:
            "Le compte Auth n a pas renvoye d identifiant. Verifiez la fonction.",
        },
        500,
      );
    }

    const { error: profileErr } = await adminClient.from("profiles").insert({
      id: userId,
      full_name: fullName,
      role: "contribuable",
      commune_id: null,
      taxpayer_identifier: taxpayerIdentifier,
    });

    if (profileErr) {
      await adminClient.auth.admin.deleteUser(userId);
      return jsonResponse(
        { error: `Profil non cree : ${profileErr.message}` },
        500,
      );
    }

    return jsonResponse({
      user_id: userId,
      email,
      taxpayer_identifier: taxpayerIdentifier,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Erreur interne inattendue";
    return jsonResponse({ error: message }, 500);
  }
});
