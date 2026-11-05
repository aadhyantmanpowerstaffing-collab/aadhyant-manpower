// Candidate WhatsApp OTP transport foundation.
// Not a registration authorization endpoint: downstream registration MUST also
// enforce a server-side proof before making OTP mandatory.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const allowedOrigins = new Set([
  "https://aadhyantmanpower.in",
  "https://www.aadhyantmanpower.in",
]);
const json = (data: unknown, status: number, origin: string) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json",
      "cache-control": "no-store",
      "access-control-allow-origin": origin,
      "vary": "Origin",
    },
  });
const env = (key: string) => Deno.env.get(key)?.trim() || "";
const phoneFormat = /^91[6-9][0-9]{9}$/;
const otpFormat = /^[0-9]{6}$/;
const encoder = new TextEncoder();
async function digest(secret: string, phone: string, otp: string) {
  const bytes = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(secret + ":" + phone + ":" + otp),
  );
  return Array.from(new Uint8Array(bytes)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
function constantTimeEqual(a: string, b: string) {
  const aa = encoder.encode(a), bb = encoder.encode(b);
  if (aa.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < aa.length; i++) diff |= aa[i] ^ bb[i];
  return diff === 0;
}
function randomOtp() {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return String(bytes[0] % 1000000).padStart(6, "0");
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin") || "";
  if (!allowedOrigins.has(origin)) return new Response("Forbidden", { status: 403 });
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": origin,
        "access-control-allow-methods": "POST, OPTIONS",
        "access-control-allow-headers": "content-type, apikey, authorization",
        "vary": "Origin",
      },
    });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, origin);
  const secret = env("CANDIDATE_OTP_HASH_SECRET");
  const supabaseUrl = env("SUPABASE_URL");
  const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
  const metaToken = env("META_WA_ACCESS_TOKEN");
  const senderId = env("META_WA_PHONE_NUMBER_ID");
  const template = env("META_WA_OTP_TEMPLATE_NAME");
  if (!secret || !supabaseUrl || !serviceKey || !metaToken || !senderId || !template) {
    return json({ error: "OTP service is awaiting provider approval" }, 503, origin);
  }
  let body: Record<string, unknown>;
  try {
    if (Number(req.headers.get("content-length") || "0") > 2048) throw Error();
    body = await req.json();
  } catch {
    return json({ error: "Invalid request" }, 400, origin);
  }
  const phone = String(body.phone || "").replace(/^\+/, "");
  const action = body.action;
  if (!phoneFormat.test(phone) || (action !== "request" && action !== "verify")) {
    return json({ error: "Invalid phone or action" }, 400, origin);
  }
  const db = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: record, error: readError } = await db.from("candidate_phone_otp")
    .select("otp_hash,expires_at,last_sent_at,window_started_at,sends_in_window,verify_attempts,verified_at")
    .eq("phone", phone).maybeSingle();
  if (readError) return json({ error: "OTP service unavailable" }, 503, origin);
  const now = Date.now();
  if (action === "request") {
    if (record && now - Date.parse(record.last_sent_at) < 60_000) {
      return json({ error: "Please retry after 60 seconds" }, 429, origin);
    }
    const sameWindow = record && now - Date.parse(record.window_started_at) < 86_400_000;
    if (sameWindow && record.sends_in_window >= 3) {
      return json({ error: "OTP request limit reached" }, 429, origin);
    }
    const otp = randomOtp();
    const hash = await digest(secret, phone, otp);
    const { error: saveError } = await db.from("candidate_phone_otp").upsert({
      phone, otp_hash: hash,
      expires_at: new Date(now + 300_000).toISOString(),
      last_sent_at: new Date(now).toISOString(),
      window_started_at: sameWindow ? record.window_started_at : new Date(now).toISOString(),
      sends_in_window: sameWindow ? record.sends_in_window + 1 : 1,
      verify_attempts: 0,
      verified_at: null,
    }, { onConflict: "phone" });
    if (saveError) return json({ error: "OTP service unavailable" }, 503, origin);

    const response = await fetch(
      "https://graph.facebook.com/v23.0/" + encodeURIComponent(senderId) + "/messages",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer " + metaToken,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to: phone,
          type: "template",
          template: {
            name: template,
            language: { code: "en" },
            components: [
              { type: "body", parameters: [{ type: "text", text: otp }] },
              { type: "button", sub_type: "url", index: "0",
                parameters: [{ type: "text", text: otp }] },
            ],
          },
        }),
      },
    ).catch(() => null);
    if (!response?.ok) {
      // The challenge is not usable when delivery request fails. Never return OTP.
      await db.from("candidate_phone_otp").update({
        expires_at: new Date(0).toISOString(),
      }).eq("phone", phone).eq("otp_hash", hash);
      return json({ error: "WhatsApp OTP could not be sent" }, 503, origin);
    }
    return json({ sent: true, expiresInSeconds: 300 }, 200, origin);
  }

  const supplied = String(body.otp || "");
  if (!otpFormat.test(supplied)) return json({ verified: false }, 400, origin);
  if (!record || record.verified_at || Date.parse(record.expires_at) <= now
    || record.verify_attempts >= 5) {
    return json({ verified: false }, 400, origin);
  }
  // Failed attempts are counted without leaking whether the number exists.
  const { error: attemptsError } = await db.from("candidate_phone_otp")
    .update({ verify_attempts: record.verify_attempts + 1 })
    .eq("phone", phone).eq("otp_hash", record.otp_hash)
    .eq("verify_attempts", record.verify_attempts);
  if (attemptsError) return json({ error: "OTP service unavailable" }, 503, origin);
  const verified = constantTimeEqual(await digest(secret, phone, supplied), record.otp_hash);
  if (!verified) return json({ verified: false }, 400, origin);
  const { error: verifyError } = await db.from("candidate_phone_otp")
    .update({ verified_at: new Date(now).toISOString() })
    .eq("phone", phone).eq("otp_hash", record.otp_hash);
  if (verifyError) return json({ error: "OTP service unavailable" }, 503, origin);
  // Intentionally no registration token yet; a separate atomic proof handoff
  // must be completed before connecting this endpoint to public registration.
  return json({ verified: true }, 200, origin);
});
