import { createClient } from "npm:@supabase/supabase-js@2";

function normalizeWhatsAppNumber(value: unknown): string {
  let digits = String(value ?? "").replace(/\D/g, "");
  if (digits.startsWith("00")) digits = digits.slice(2);
  else if (digits.startsWith("0")) digits = `243${digits.slice(1)}`;
  return digits;
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

async function isValidSignature(rawBody: Uint8Array, signature: string, appSecret: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(appSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = new Uint8Array(await crypto.subtle.sign("HMAC", key, rawBody));
  const expected = `sha256=${[...digest].map(byte => byte.toString(16).padStart(2, "0")).join("")}`;
  return constantTimeEqual(expected, signature.toLowerCase());
}

Deno.serve(async (request: Request) => {
  const verifyToken = Deno.env.get("WHATSAPP_WEBHOOK_VERIFY_TOKEN");
  if (!verifyToken) return new Response("Webhook non configuré.", { status: 503 });

  if (request.method === "GET") {
    const url = new URL(request.url);
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");
    if (mode === "subscribe" && token === verifyToken && challenge) {
      return new Response(challenge, { status: 200 });
    }
    return new Response("Vérification refusée.", { status: 403 });
  }

  if (request.method !== "POST") return new Response("Méthode non autorisée.", { status: 405 });

  const appSecret = Deno.env.get("WHATSAPP_APP_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!appSecret || !supabaseUrl || !serviceRoleKey) {
    console.error("WhatsApp webhook secrets are incomplete.");
    return new Response("Webhook non configuré.", { status: 503 });
  }

  const rawBody = new Uint8Array(await request.arrayBuffer());
  const signature = request.headers.get("x-hub-signature-256") || "";
  if (!signature || !await isValidSignature(rawBody, signature, appSecret)) {
    return new Response("Signature invalide.", { status: 401 });
  }

  let payload: {
    entry?: Array<{
      changes?: Array<{
        value?: {
          messages?: Array<{
            from?: string;
            text?: { body?: string };
            button?: { text?: string };
            interactive?: {
              button_reply?: { title?: string };
              list_reply?: { title?: string };
            };
          }>;
        };
      }>;
    }>;
  };
  try {
    payload = JSON.parse(new TextDecoder().decode(rawBody));
  } catch {
    return new Response("JSON invalide.", { status: 400 });
  }

  const optOutCommands = new Set(["stop", "stopall", "unsubscribe", "cancel", "end", "quit", "arret"]);
  const senders = new Set<string>();
  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      for (const message of change.value?.messages ?? []) {
        const text = [
          message.text?.body,
          message.button?.text,
          message.interactive?.button_reply?.title,
          message.interactive?.list_reply?.title,
        ].find(value => value);
        const command = String(text ?? "").trim().normalize("NFD")
          .replace(/\p{Diacritic}/gu, "").toLowerCase().replace(/[^a-z]/g, "");
        if (message.from && optOutCommands.has(command)) {
          senders.add(normalizeWhatsAppNumber(message.from));
        }
      }
    }
  }

  if (!senders.size) return new Response("OK", { status: 200 });

  const serviceClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const memberIds: Array<{ assembly_id: string; proclamateur_id: string }> = [];
  const pageSize = 1000;
  for (let offset = 0; ; offset += pageSize) {
    const { data: people, error: peopleError } = await serviceClient
      .from("app_sync_records")
      .select("assembly_id,record_id,payload")
      .eq("database_name", "ProclamateursDB")
      .eq("store_name", "proclamateurs")
      .is("deleted_at", null)
      .range(offset, offset + pageSize - 1);
    if (peopleError) {
      console.error("Unable to locate WhatsApp opt-out:", peopleError.message);
      return new Response("Impossible de traiter le désabonnement.", { status: 500 });
    }
    for (const person of people ?? []) {
      if (senders.has(normalizeWhatsAppNumber(person.payload?.telephone))) {
        memberIds.push({ assembly_id: person.assembly_id, proclamateur_id: person.record_id });
      }
    }
    if (!people || people.length < pageSize) break;
  }

  for (const member of memberIds) {
    const { error } = await serviceClient
      .from("assembly_whatsapp_consents")
      .update({ consented: false, revoked_at: new Date().toISOString(), updated_at: new Date().toISOString() })
      .eq("assembly_id", member.assembly_id)
      .eq("proclamateur_id", member.proclamateur_id)
      .eq("consented", true);
    if (error) {
      console.error("Unable to revoke WhatsApp consent:", error.message);
      return new Response("Impossible de traiter le désabonnement.", { status: 500 });
    }
  }

  return new Response("OK", { status: 200 });
});
