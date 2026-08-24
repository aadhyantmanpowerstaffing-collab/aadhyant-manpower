import { parseWhatsAppWebhook, summarizeEvent } from "../_shared/whatsapp/parser.ts";
import { constantTimeEqual, sha256Hex, verifyMetaSignature } from "../_shared/whatsapp/signature.ts";
import type { AcceptedWebhookEvent, NormalizedWebhookEvent, WebhookEnvironment } from "../_shared/whatsapp/types.ts";

const MAX_BODY_BYTES = 1_048_576;

type AcceptEvent = (event: AcceptedWebhookEvent) => Promise<string | void>;
type ProcessEvent = (webhookEventId: string, event: NormalizedWebhookEvent, payloadHash: string) => Promise<void>;
type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;

const response = (body: string, status: number): Response => new Response(body, {
  status,
  headers: { "content-type": "text/plain; charset=utf-8" },
});

export async function handleWhatsAppWebhook(
  request: Request,
  environment: WebhookEnvironment,
  acceptEvent: AcceptEvent,
  processEvent?: ProcessEvent,
): Promise<Response> {
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
  try {
    if (events.length === 0) {
      await acceptEvent({ provider_event_key: `unknown:${payloadHash}`, payload_sha256: payloadHash, event_category: "unknown", redacted_payload: {} });
    } else {
      for (const event of events) {
        const webhookEventId = await acceptEvent({
          provider_event_key: event.providerEventKey,
          payload_sha256: payloadHash,
          event_category: event.category,
          redacted_payload: summarizeEvent(event),
        });
        if (webhookEventId && processEvent) {
          await processEvent(webhookEventId, event, payloadHash);
        }
      }
    }
  } catch {
    return response("Event processing failed", 500);
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

async function callSupabaseRpc(
  environment: WebhookEnvironment,
  fetcher: Fetcher,
  rpcName: string,
  body: Record<string, unknown>,
): Promise<unknown> {
  if (!environment.supabaseUrl || !environment.supabaseSecretKey) throw new Error("Server database configuration is unavailable");
  const result = await fetcher(`${environment.supabaseUrl}/rest/v1/rpc/${rpcName}`, {
    method: "POST",
    headers: {
      apikey: environment.supabaseSecretKey,
      authorization: `Bearer ${environment.supabaseSecretKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!result.ok) throw new Error(`Webhook persistence failed (${result.status})`);
  return result.json();
}

async function findOutboundMessageId(
  environment: WebhookEnvironment,
  fetcher: Fetcher,
  providerMessageId: string,
): Promise<string> {
  if (!environment.supabaseUrl || !environment.supabaseSecretKey) throw new Error("Server database configuration is unavailable");
  const url = new URL(`${environment.supabaseUrl}/rest/v1/whatsapp_outbound_messages`);
  url.searchParams.set("select", "id");
  url.searchParams.set("provider_message_id", `eq.${providerMessageId}`);
  url.searchParams.set("limit", "2");
  const result = await fetcher(url, {
    method: "GET",
    headers: {
      apikey: environment.supabaseSecretKey,
      authorization: `Bearer ${environment.supabaseSecretKey}`,
      accept: "application/json",
    },
  });
  if (!result.ok) throw new Error(`Webhook outbound lookup failed (${result.status})`);
  const rows: unknown = await result.json();
  if (!Array.isArray(rows) || rows.length !== 1 || typeof rows[0]?.id !== "string" || !rows[0].id) {
    throw new Error("Webhook status has no unique outbound message linkage");
  }
  return rows[0].id;
}

export function createSupabaseWebhookPersistence(environment: WebhookEnvironment, fetcher: Fetcher = fetch) {
  return {
    async acceptEvent(event: AcceptedWebhookEvent): Promise<string> {
      const id = await callSupabaseRpc(environment, fetcher, "accept_whatsapp_webhook_event", {
        p_provider_event_key: event.provider_event_key,
        p_payload_sha256: event.payload_sha256,
        p_event_category: event.event_category,
        p_redacted_payload: event.redacted_payload,
      });
      if (typeof id !== "string" || !id) throw new Error("Webhook persistence returned an invalid identifier");
      return id;
    },
    async processEvent(webhookEventId: string, event: NormalizedWebhookEvent, payloadHash: string): Promise<void> {
      if (!event.providerMessageId) throw new Error("Webhook event is missing its provider message identifier");
      if (event.category === "message_status") {
        if (!event.status) throw new Error("Webhook status is missing its normalized state");
        const outboundMessageId = await findOutboundMessageId(environment, fetcher, event.providerMessageId);
        await callSupabaseRpc(environment, fetcher, "record_whatsapp_message_event", {
          p_outbound_message_id: outboundMessageId,
          p_webhook_event_id: webhookEventId,
          p_provider_event_key: event.providerEventKey,
          p_provider_message_id: event.providerMessageId,
          p_status: event.status,
          p_provider_timestamp: event.providerTimestamp ?? null,
          p_payload_sha256: payloadHash,
          p_provider_error_category: event.errorCategory ?? null,
          p_provider_error_code: event.errorCode ?? null,
        });
        return;
      }
      if (!event.phone || !event.messageType) throw new Error("Inbound event is missing normalized identifiers");
      const contactId = await callSupabaseRpc(environment, fetcher, "upsert_whatsapp_inbound_contact", { p_phone: event.phone });
      if (typeof contactId !== "string" || !contactId) throw new Error("Contact persistence returned an invalid identifier");
      await callSupabaseRpc(environment, fetcher, "record_whatsapp_inbound_message", {
        p_webhook_event_id: webhookEventId,
        p_contact_id: contactId,
        p_provider_message_id: event.providerMessageId,
        p_provider_timestamp: event.providerTimestamp ?? null,
        p_message_type: event.messageType,
        p_safe_text: null,
        p_action_id: event.actionId ?? null,
        p_correlation_key: event.correlationKey ?? null,
        p_redacted_response: event.redactedResponse ?? null,
      });
    },
  };
}

export default {
  fetch(request: Request): Promise<Response> {
    const environment = runtimeEnvironment();
    const persistence = createSupabaseWebhookPersistence(environment);
    return handleWhatsAppWebhook(request, environment, persistence.acceptEvent, persistence.processEvent);
  },
};
