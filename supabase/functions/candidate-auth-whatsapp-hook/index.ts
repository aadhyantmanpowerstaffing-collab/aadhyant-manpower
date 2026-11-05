// Supabase Auth "Send SMS" hook that delivers Supabase's OTP through an approved
// Meta WhatsApp Authentication template. Configure through Auth > Hooks after
// approval, with verify_jwt=false and a Standard Webhooks signing secret.
// Prefer this hook over independently implementing authentication tokens.
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";
const env = (key: string) => Deno.env.get(key)?.trim() || "";
const json = (status: number) => new Response(JSON.stringify({}), {
  status,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405);
  const secret = env("SEND_SMS_HOOK_SECRET");
  const accessToken = env("META_WA_ACCESS_TOKEN");
  const senderId = env("META_WA_PHONE_NUMBER_ID");
  const templateName = env("META_WA_OTP_TEMPLATE_NAME");
  const templateLanguage = env("META_WA_OTP_TEMPLATE_LANGUAGE") || "en_US";
  if (!secret || !accessToken || !senderId || !templateName) return json(503);
  let payload = "";
  try {
    if (Number(req.headers.get("content-length") || "0") > 16_384) return json(413);
    payload = await req.text();
    if (payload.length > 16_384) return json(413);
  } catch { return json(400); }

  let event: { user?: { phone?: string }, sms?: { otp?: string } };
  try {
    const webhookSecret = secret.replace(/^v1,whsec_/, "");
    event = new Webhook(webhookSecret).verify(payload, Object.fromEntries(req.headers));
  } catch { return json(401); }
  const phone = String(event.user?.phone || "").replace(/[^0-9]/g, "");
  const otp = String(event.sms?.otp || "");
  if (!/^91[6-9][0-9]{9}$/.test(phone) || !/^[0-9]{6}$/.test(otp)) return json(400);

  const meta = await fetch(
    "https://graph.facebook.com/v23.0/" + encodeURIComponent(senderId) + "/messages",
    {
      method: "POST",
      headers: {
        authorization: "Bearer " + accessToken,
        "content-type": "application/json",
      },
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
    },
  ).catch(() => null);
  if (!meta?.ok) return json(502);
  return json(200);
});
