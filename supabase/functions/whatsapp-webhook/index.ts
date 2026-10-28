import {isEmployerPostJob,sendEmployerPostJob} from '../_shared/whatsapp/employer-post-job.ts';
import { parseWhatsAppWebhook, summarizeEvent } from "../_shared/whatsapp/parser.ts";
import { constantTimeEqual, sha256Hex, verifyMetaSignature } from "../_shared/whatsapp/signature.ts";
import { runtimeServerKey, serverDatabaseHeaders } from "../_shared/whatsapp/server-headers.ts";
import { sendRegistrationReply } from "../_shared/whatsapp/registration-reply.ts";
import { sendRegistrationChat } from "../_shared/whatsapp/registration-chat.ts";
import type { AcceptedWebhookEvent, NormalizedWebhookEvent, WebhookEnvironment } from "../_shared/whatsapp/types.ts";

const MAX_BODY_BYTES = 1_048_576;

export function parseSharingSubscription(event: NormalizedWebhookEvent): Record<string, unknown> | null {
  const prefix = "SUBSCRIBE JOB UPDATES ";
  if (event.messageType !== "text" || !event.safeText?.startsWith(prefix)) return null;
  try {
    const p = JSON.parse(event.safeText.slice(prefix.length));
    if (!p || typeof p !== "object" || Array.isArray(p) || !["all", "filtered"].includes(p.scope)
      || Object.keys(p).some(k => !["scope", "locations", "trades"].includes(k))) return null;
    for (const k of ["locations", "trades"]) {
      if (!Array.isArray(p[k]) || p[k].length > 20 || p[k].some((v: unknown) => typeof v !== "string" || !v.trim() || v.length > 160)) return null;
    }
    const count = p.locations.length + p.trades.length;
    if ((p.scope === "all" && count !== 0) || (p.scope === "filtered" && count === 0)) return null;
    return p;
  } catch { return null; }
}

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
  resolveIdentity?: () => Promise<{businessAccountId:string;phoneNumberId:string}>,
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
  let identity={businessAccountId:environment.businessAccountId,phoneNumberId:environment.phoneNumberId};
  try { if(resolveIdentity)identity=await resolveIdentity(); } catch { return response("Webhook sender setup pending",503); }
  if(identity.businessAccountId||identity.phoneNumberId){
    const root=payload as any;
    if(!Array.isArray(root?.entry)||root.entry.some((entry:any)=>entry.id!==identity.businessAccountId||!Array.isArray(entry.changes)||entry.changes.some((change:any)=>change.value?.metadata?.phone_number_id!==identity.phoneNumberId)))return response("Webhook sender mismatch",403);
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
    accessToken: get("WHATSAPP_ACCESS_TOKEN"),
    businessAccountId: get("WHATSAPP_BUSINESS_ACCOUNT_ID"),
    appSecret: get("WHATSAPP_APP_SECRET"),
    verifyToken: get("WHATSAPP_WEBHOOK_VERIFY_TOKEN"),
    supabaseUrl: get("SUPABASE_URL"),
    supabaseSecretKey: runtimeServerKey(get),
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
    redirect: "error",
    headers: {
      ...serverDatabaseHeaders(environment.supabaseSecretKey),
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(10000),
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
    redirect: "error",
    headers: {
      ...serverDatabaseHeaders(environment.supabaseSecretKey),
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
      const sharingPreferences = parseSharingSubscription(event);
      const postJob=(event.messageType==='text'&&isEmployerPostJob(event.safeText))||(event.messageType==='button'&&event.actionId==='POST_JOB');
      const inboundMessageId = await callSupabaseRpc(environment, fetcher, "record_whatsapp_inbound_message", {
        p_webhook_event_id: webhookEventId,
        p_contact_id: contactId,
        p_provider_message_id: event.providerMessageId,
        p_provider_timestamp: event.providerTimestamp ?? null,
        p_message_type: event.messageType,
        // Only the canonical private store receives bounded text. The event ledger
        // remains summary-only; the database excludes registration/sensitive data.
        p_safe_text: ['text','button','list'].includes(event.messageType) ? event.safeText ?? null : null,
        p_action_id: postJob ? "POST_JOB" : sharingPreferences ? "SUBSCRIBE_JOB_UPDATES" : event.actionId ?? null,
        p_correlation_key: event.correlationKey ?? null,
        p_redacted_response: event.redactedResponse ?? null,
      });
      if (typeof inboundMessageId !== "string" || !inboundMessageId) throw new Error("Inbound persistence returned an invalid identifier");
      // Exact STOP/UNSUBSCRIBE only. Registration, arbitrary text and INTERESTED
      // never opt a contact into marketing. No acknowledgement message is sent.
      const stop = ["STOP", "UNSUBSCRIBE"].includes(event.actionId?.trim().toUpperCase() ?? "")
        || (event.messageType === "text" && ["STOP", "UNSUBSCRIBE"].includes(event.safeText?.trim().toUpperCase() ?? ""));
      if (stop) {
        const suppressed = await callSupabaseRpc(environment, fetcher, "set_whatsapp_contact_suppression", {
          p_contact_id: contactId, p_suppressed: true, p_source: "whatsapp_inbound", p_reason_category: "user_stop",
        });
        if (suppressed !== true) throw new Error("Contact suppression was not confirmed");
        await callSupabaseRpc(environment,fetcher,'console_cancel_registration_chat',{p_contact_id:contactId});
        return;
      }
      if(postJob){
        const reply:any=await callSupabaseRpc(environment,fetcher,'console_process_employer_post_job',{p_inbound_message_id:inboundMessageId});
        if(reply?.outbound_id){
          const config:any=await callSupabaseRpc(environment,fetcher,'console_sender_configuration',{});
          if(config?.account_id===environment.businessAccountId)await sendEmployerPostJob(reply.outbound_id,(name,body)=>callSupabaseRpc(environment,fetcher,name,body),config,environment.accessToken||'',fetcher);
        }
        return;
      }
      if (event.messageType === 'flow' && event.actionId === 'REGISTRATION_SUBMIT') {
        try {
          await callSupabaseRpc(environment,fetcher,'console_process_registration_flow',{p_inbound_message_id:inboundMessageId});
        } catch {
          // Durable attention, no infinite retries of invalid registration data.
          // An already-committed success is never overwritten after an HTTP timeout.
          await callSupabaseRpc(environment,fetcher,'console_registration_flow_failure',{p_inbound_message_id:inboundMessageId});
        }
        return;
      }
      if (sharingPreferences) {
        await callSupabaseRpc(environment, fetcher, "subscribe_whatsapp_sharing_updates", {
          p_inbound_message_id: inboundMessageId, p_preferences: sharingPreferences,
        });
        return;
      }
      if (event.actionId?.trim().toUpperCase() === "INTERESTED") {
        const interested: any = await callSupabaseRpc(environment, fetcher, "console_process_interested", {
          p_inbound_message_id: inboundMessageId,
        });
        if (interested?.status === 'registration_required') {
          const chat:any=await callSupabaseRpc(environment,fetcher,'console_process_registration_chat',{p_inbound_message_id:inboundMessageId,p_text:null});
          const config: any = await callSupabaseRpc(environment, fetcher, 'console_sender_configuration', {});
          if (config?.account_id === environment.businessAccountId) {
            if(chat?.handled===true){
              if(chat.outbound_id)await sendRegistrationChat(chat.outbound_id,(name,body)=>callSupabaseRpc(environment,fetcher,name,body),config,environment.accessToken||'',fetcher);
            }else await sendRegistrationReply(inboundMessageId,
              (name, body) => callSupabaseRpc(environment, fetcher, name, body), config, environment.accessToken || '', fetcher);
          }
        }
        return;
      }
      const sessionTimestamp=Date.parse(event.providerTimestamp??'');
      if(['text','button','list'].includes(event.messageType)&&Number.isFinite(sessionTimestamp)
        &&sessionTimestamp<=Date.now()&&sessionTimestamp>Date.now()-86400000) {
        const chat:any=await callSupabaseRpc(environment,fetcher,'console_process_registration_chat',{p_inbound_message_id:inboundMessageId,p_text:event.messageType==='text'?event.safeText??null:null});
        if(chat?.handled===true&&chat.outbound_id){
          const config:any=await callSupabaseRpc(environment,fetcher,'console_sender_configuration',{});
          if(config?.account_id===environment.businessAccountId)await sendRegistrationChat(chat.outbound_id,(name,body)=>callSupabaseRpc(environment,fetcher,name,body),config,environment.accessToken||'',fetcher);
        }
      }
    },
  };
}

const runtimeHandler={
  fetch(request: Request): Promise<Response> {
    const environment = runtimeEnvironment();
    const persistence = createSupabaseWebhookPersistence(environment);
    return handleWhatsAppWebhook(request, environment, persistence.acceptEvent, persistence.processEvent,async()=>{
      const config:any=await callSupabaseRpc(environment,fetch,"console_sender_configuration",{});
      if(!config?.account_id||!config?.phone_id)throw new Error("Verified sender identity required");
      return {businessAccountId:config.account_id,phoneNumberId:config.phone_id};
    });
  },
};

export default runtimeHandler;
const deno=(globalThis as any).Deno;if(deno?.serve)deno.serve(runtimeHandler.fetch);
