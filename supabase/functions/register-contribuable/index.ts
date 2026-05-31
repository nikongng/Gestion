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
    const taxpayerEmail = String(body.taxpayer_email ?? email).trim()
      .toLowerCase();
    const taxpayerPhone = String(body.taxpayer_phone ?? "").trim();
    const taxpayerAddress = String(body.taxpayer_address ?? "").trim();
    const isLegalEntity = body.is_legal_entity === true;
    const legalDenomination = String(body.legal_denomination ?? "").trim();
    const legalNif = String(body.legal_nif ?? "").trim();
    const communeId =
      typeof body.commune_id === "string" && body.commune_id.trim()
        ? body.commune_id.trim()
        : null;
    const taxpayerIdType = String(body.taxpayer_id_type ?? "").trim();
    const taxpayerIdNumber = String(body.taxpayer_id_number ?? "").trim();
    const taxpayerLocationLabel = String(
      body.taxpayer_location_label ?? "",
    ).trim();
    const taxpayerActivity = String(body.taxpayer_activity ?? "").trim();
    const taxpayerStatus = String(body.taxpayer_status ?? "actif").trim() ||
      "actif";

    if (!email || !password || !fullName || !taxpayerPhone || !taxpayerAddress) {
      return jsonResponse(
        {
          error:
            "email, password, full_name, taxpayer_phone et taxpayer_address requis",
        },
        400,
      );
    }

    if (isLegalEntity && (!legalDenomination || !legalNif)) {
      return jsonResponse(
        { error: "legal_denomination et legal_nif requis" },
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
          taxpayer_email: taxpayerEmail,
          taxpayer_phone: taxpayerPhone,
          taxpayer_address: taxpayerAddress,
          is_legal_entity: isLegalEntity,
          legal_denomination: legalDenomination,
          legal_nif: legalNif,
          commune_id: communeId,
          taxpayer_id_type: taxpayerIdType,
          taxpayer_id_number: taxpayerIdNumber,
          taxpayer_location_label: taxpayerLocationLabel,
          taxpayer_activity: taxpayerActivity,
          taxpayer_status: taxpayerStatus,
          account_status: taxpayerStatus === "inactif" ? "inactif" : "actif",
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
      roles: ["contribuable"],
      commune_id: null,
      taxpayer_identifier: taxpayerIdentifier,
      taxpayer_email: taxpayerEmail,
      taxpayer_phone: taxpayerPhone,
      taxpayer_address: taxpayerAddress,
      is_legal_entity: isLegalEntity,
      legal_denomination: isLegalEntity ? legalDenomination : null,
      legal_nif: isLegalEntity ? legalNif : null,
      legal_representative_name: isLegalEntity ? fullName : null,
      taxpayer_id_type: taxpayerIdType || null,
      taxpayer_id_number: taxpayerIdNumber || null,
      taxpayer_location_label: taxpayerLocationLabel || null,
      taxpayer_activity: taxpayerActivity || null,
      taxpayer_status: taxpayerStatus,
      account_status: taxpayerStatus === "inactif" ? "inactif" : "actif",
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
