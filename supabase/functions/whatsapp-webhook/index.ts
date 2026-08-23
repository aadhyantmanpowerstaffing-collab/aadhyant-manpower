import { parseWhatsAppWebhook, summarizeEvent } from "../_shared/whatsapp/parser.ts";
import { constantTimeEqual, sha256Hex, verifyMetaSignature } from "../_shared/whatsapp/signature.ts";
import type { AcceptedWebhookEvent, WebhookEnvironment } from "../_shared/whatsapp/types.ts";

const MAX_BODY_BYTES = 1_048_576;

type AcceptEvent = (event: AcceptedWebhookEvent) => Promise<void>;

const response = (body: string, status: number): Response => new Response(body, {
  status,
  headers: { "content-type": "text/plain; charset=utf-8" },
});

export async function handleWhatsAppWebhook(request: Request, environment: WebhookEnvironment, acceptEvent: AcceptEvent): Promise<Response> {
  const url = new URL(request.url);
  if (request.method === "GET") {
    const valid = url.searchParams.get("hub.mode") === "subscribe"
      && Boolean(environment.verifyToken)
      && constantTimeEqual(url.searchParams.get("hub.verify_token") ?? "", environment.verifyToken)
      && url.searchParams.has("hub.challenge");
    return response(valid ? url.searchParams.get("hub.challenge")! : "Forbidden", valid ? 200 : 403);
  }
  if (request.method !== "POST") return response("Method not allowed", 405);
  const contentType = request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "application/json") return response("Unsupported content type", 415);
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) return response("Payload too large", 413);

  const rawBody = new Uint8Array(await request.arrayBuffer());
  if (rawBody.byteLength === 0 || rawBody.byteLength > MAX_BODY_BYTES) return response("Payload size is invalid", rawBody.byteLength > MAX_BODY_BYTES ? 413 : 400);
  const signature = request.headers.get("x-hub-signature-256");
  if (!await verifyMetaSignature(rawBody, signature, environment.appSecret)) return response("Invalid signature", 403);

  let payload: unknown;
  try {
    payload = JSON.parse(new TextDecoder().decode(rawBody));
  } catch {
    return response("Invalid JSON", 400);
  }
  const payloadHash = await sha256Hex(rawBody);
  const events = parseWhatsAppWebhook(payload);
  if (events.length === 0) {
    await acceptEvent({ provider_event_key: `unknown:${payloadHash}`, payload_sha256: payloadHash, event_category: "unknown", redacted_payload: {} });
  } else {
    for (const event of events) {
      await acceptEvent({
        provider_event_key: event.providerEventKey,
        payload_sha256: payloadHash,
        event_category: event.category,
        redacted_payload: summarizeEvent(event),
      });
    }
  }
  return response("EVENT_RECEIVED", 200);
}

function runtimeEnvironment(): WebhookEnvironment {
  const deno = (globalThis as unknown as { Deno?: { env: { get(name: string): string | undefined } } }).Deno;
  const get = (name: string): string => deno?.env.get(name) ?? "";
  return {
    appSecret: get("WHATSAPP_APP_SECRET"),
    verifyToken: get("WHATSAPP_WEBHOOK_VERIFY_TOKEN"),
    supabaseUrl: get("SUPABASE_URL"),
    supabaseSecretKey: get("SUPABASE_SECRET_KEY") || get("SUPABASE_SERVICE_ROLE_KEY"),
  };
}

async function acceptWithSupabase(environment: WebhookEnvironment, event: AcceptedWebhookEvent): Promise<void> {
  if (!environment.supabaseUrl || !environment.supabaseSecretKey) throw new Error("Server database configuration is unavailable");
  const result = await fetch(`${environment.supabaseUrl}/rest/v1/rpc/accept_whatsapp_webhook_event`, {
    method: "POST",
    headers: {
      apikey: environment.supabaseSecretKey,
      authorization: `Bearer ${environment.supabaseSecretKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      p_provider_event_key: event.provider_event_key,
      p_payload_sha256: event.payload_sha256,
      p_event_category: event.event_category,
      p_redacted_payload: event.redacted_payload,
    }),
  });
  if (!result.ok) throw new Error(`Webhook event acceptance failed (${result.status})`);
}

export default {
  fetch(request: Request): Promise<Response> {
    const environment = runtimeEnvironment();
    return handleWhatsAppWebhook(request, environment, (event) => acceptWithSupabase(environment, event));
  },
};
