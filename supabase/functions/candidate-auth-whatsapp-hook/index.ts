// Supabase Auth "Send SMS" hook. It forwards a Supabase-generated OTP through
// an approved Meta WhatsApp Authentication template and never exposes the code.
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

const encoder = new TextEncoder();
const env = (key: string) => Deno.env.get(key)?.trim() || "";
const json = (status: number, retryAfterSeconds?: number) => new Response(JSON.stringify({}), {
  status,
  headers: {
    "content-type": "application/json",
    "cache-control": "no-store",
    ...(retryAfterSeconds ? { "retry-after": String(retryAfterSeconds) } : {}),
  },
});

function runtimeServerKey() {
  const explicit = env("SUPABASE_SECRET_KEY");
  if (explicit) return explicit;
  const injected = env("SUPABASE_SECRET_KEYS");
  if (injected) {
    try {
      const parsed: unknown = JSON.parse(injected);
      if (parsed && typeof parsed === "object" && typeof (parsed as Record<string, unknown>).default === "string") {
        return (parsed as Record<string, string>).default;
      }
    } catch { /* Never log secret configuration. */ }
  }
  return env("SUPABASE_SERVICE_ROLE_KEY");
}

function databaseHeaders(key: string) {
  const headers: Record<string, string> = { apikey: key, "content-type": "application/json" };
  if (!key.startsWith("sb_secret_")) headers.authorization = `Bearer ${key}`;
  return headers;
}

function hex(bytes: ArrayBuffer) {
  return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function hmac(secret: string, value: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return hex(await crypto.subtle.sign("HMAC", key, encoder.encode(value)));
}

async function rpc(
  base: string,
  key: string,
  name: string,
  args: Record<string, string>,
  timeoutMilliseconds: number,
) {
  try {
    const response = await fetch(`${base}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: databaseHeaders(key),
      body: JSON.stringify(args),
      redirect: "error",
      signal: AbortSignal.timeout(timeoutMilliseconds),
    });
    if (!response.ok) return null;
    const result: unknown = await response.json();
    return typeof result === "string" ? result : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405);

  const hookSecret = env("SEND_SMS_HOOK_SECRET");
  const metaToken = env("WHATSAPP_ACCESS_TOKEN");
  const senderId = env("WHATSAPP_PHONE_NUMBER_ID");
  const templateName = env("META_WA_OTP_TEMPLATE_NAME");
  const templateLanguage = env("META_WA_OTP_TEMPLATE_LANGUAGE") || "en_US";
  const databaseUrl = env("SUPABASE_URL");
  const databaseKey = runtimeServerKey();
  if (!hookSecret || !metaToken || !senderId || !templateName || !databaseUrl || !databaseKey) {
    return json(503, 30);
  }

  let payload = "";
  try {
    if (Number(req.headers.get("content-length") || "0") > 16_384) return json(413);
    payload = await req.text();
    if (payload.length > 16_384) return json(413);
  } catch {
    return json(400);
  }

  let event: { user?: { phone?: string }, sms?: { otp?: string } };
  try {
    const secret = hookSecret.replace(/^v1,whsec_/, "");
    event = new Webhook(secret).verify(payload, Object.fromEntries(req.headers));
  } catch {
    return json(401);
  }

  const phone = String(event.user?.phone || "").replace(/[^0-9]/g, "");
  const otp = String(event.sms?.otp || "");
  if (!/^91[6-9][0-9]{9}$/.test(phone) || !/^[0-9]{6}$/.test(otp)) return json(400);

  const phoneHash = await hmac(hookSecret, `phone:${phone}`);
  const codeHash = await hmac(hookSecret, `otp:${phone}:${otp}`);
  // Auth HTTP hooks have a five-second total budget. Keep enough time for the
  // Meta call and the completion write; a timeout never exposes an OTP.
  const reserve = await rpc(
    databaseUrl,
    databaseKey,
    "candidate_otp_dispatch_reserve",
    { p_phone_hash: phoneHash, p_code_hash: codeHash },
    700,
  );
  if (reserve === "sent") return json(200);
  if (reserve === "limited") return json(429, 86_400);
  if (reserve !== "reserved") return json(503, 5);

  let messageId = "";
  try {
    const response = await fetch(
      `https://graph.facebook.com/v25.0/${encodeURIComponent(senderId)}/messages`,
      {
        method: "POST",
        headers: { authorization: `Bearer ${metaToken}`, "content-type": "application/json" },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to: phone,
          type: "template",
          template: {
            name: templateName,
            language: { code: templateLanguage },
            components: [
              { type: "body", parameters: [{ type: "text", text: otp }] },
              {
                type: "button",
                sub_type: "url",
                index: "0",
                parameters: [{ type: "text", text: otp }],
              },
            ],
          },
        }),
        redirect: "error",
        signal: AbortSignal.timeout(2_500),
      },
    );
    const responseBody: unknown = await response.json().catch(() => null);
    const candidateId = (responseBody as { messages?: Array<{ id?: unknown }> } | null)?.messages?.[0]?.id;
    if (!response.ok || typeof candidateId !== "string" || !candidateId.startsWith("wamid.")) {
      await rpc(
        databaseUrl,
        databaseKey,
        "candidate_otp_dispatch_fail",
        { p_code_hash: codeHash },
        500,
      );
      return json(502);
    }
    messageId = candidateId;
  } catch {
    await rpc(
      databaseUrl,
      databaseKey,
      "candidate_otp_dispatch_fail",
      { p_code_hash: codeHash },
      500,
    );
    return json(502);
  }

  const completed = await rpc(
    databaseUrl,
    databaseKey,
    "candidate_otp_dispatch_complete",
    { p_code_hash: codeHash, p_provider_message_id: messageId },
    700,
  );
  return completed === "sent" ? json(200) : json(502);
});
