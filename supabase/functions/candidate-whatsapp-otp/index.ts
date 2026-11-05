// Candidate WhatsApp OTP transport foundation.
// Requires one-use verified proof for the registration endpoint.
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
  if (!phoneFormat.test(phone) || !["request", "verify", "register"].includes(String(action))) {
    return json({ error: "Invalid phone or action" }, 400, origin);
  }
  const db = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  if (action === "request") {
    const otp = randomOtp();
    const hash = await digest(secret, phone, otp);
    const { data: issue, error: issueError } = await db.rpc("candidate_otp_issue", {
      p_phone: phone,
      p_hash: hash,
    });
    if (issueError) return json({ error: "OTP service unavailable" }, 503, origin);
    if (issue !== "issued") {
      return json({
        error: issue === "cooldown" ? "Please retry after 60 seconds" : "OTP request limit reached",
      }, 429, origin);
    }
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
      await db.rpc("candidate_otp_cancel", { p_phone: phone, p_hash: hash });
      return json({ error: "WhatsApp OTP could not be sent" }, 503, origin);
    }
    return json({ sent: true, expiresInSeconds: 300 }, 200, origin);
  }

  if (action === "verify") {
    const supplied = String(body.otp || "");
    if (!otpFormat.test(supplied)) return json({ verified: false }, 400, origin);
    const proofBytes = new Uint8Array(32);
    crypto.getRandomValues(proofBytes);
    const proof = Array.from(proofBytes).map((b) => b.toString(16).padStart(2, "0")).join("");
    const { data: verified, error } = await db.rpc("candidate_otp_verify", {
      p_phone: phone,
      p_hash: await digest(secret, phone, supplied),
      p_proof_hash: await digest(secret, phone, proof),
    });
    if (error) return json({ error: "OTP service unavailable" }, 503, origin);
    if (!verified) return json({ verified: false }, 400, origin);
    return json({ verified: true, proof, proofExpiresInSeconds: 600 }, 200, origin);
  }
  if (action === "register") {
    const proof = String(body.proof || "");
    const candidate = body.candidate;
    const requirement = String(body.requirementCode || "").trim().toUpperCase();
    if (!/^[a-f0-9]{64}$/.test(proof) || !candidate || Array.isArray(candidate)
      || typeof candidate !== "object"
      || (requirement && !/^AAD-[0-9]{4}-[0-9]{6}$/.test(requirement))) {
      return json({ error: "Invalid registration request" }, 400, origin);
    }
    const { data, error } = await db.rpc("candidate_otp_register", {
      p_phone: phone,
      p_proof_hash: await digest(secret, phone, proof),
      p_candidate: candidate,
      p_requirement_code: requirement || null,
    });
    if (error) return json({ error: "Registration failed or OTP proof expired" }, 400, origin);
    return json({ registered: true, result: data }, 200, origin);
  }
  return json({ error: "Invalid action" }, 400, origin);
});
