import type { NormalizedWebhookEvent, WhatsAppEventCategory } from "./types.ts";

const MAX_SAFE_TEXT = 2_000;
const MAX_ACTION_ID = 200;
const MAX_CORRELATION = 240;

const bounded = (value: unknown, limit: number): string | undefined => {
  if (typeof value !== "string") return undefined;
  const text = value.trim();
  return text ? text.slice(0, limit) : undefined;
};

const timestamp = (value: unknown): string | undefined => {
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds <= 0) return undefined;
  return new Date(seconds * 1_000).toISOString();
};

function parseMessage(message: Record<string, unknown>): NormalizedWebhookEvent | null {
  const id = bounded(message.id, 240);
  if (!id) return null;
  const rawType = bounded(message.type, 40) ?? "unknown";
  const phone = bounded(message.from, 32);
  const base = {
    providerEventKey: `message:${id}`,
    providerMessageId: id,
    providerTimestamp: timestamp(message.timestamp),
    phone,
  };

  if (rawType === "text") {
    const text = message.text as Record<string, unknown> | undefined;
    return { ...base, category: "message", messageType: "text", safeText: bounded(text?.body, MAX_SAFE_TEXT) };
  }
  if (rawType === "button") {
    const button = message.button as Record<string, unknown> | undefined;
    return { ...base, category: "message", messageType: "button", safeText: bounded(button?.text, MAX_SAFE_TEXT), actionId: bounded(button?.payload, MAX_ACTION_ID) };
  }
  if (rawType === "interactive") {
    const interactive = message.interactive as Record<string, unknown> | undefined;
    const subtype = bounded(interactive?.type, 40);
    if (subtype === "button_reply") {
      const reply = interactive?.button_reply as Record<string, unknown> | undefined;
      return { ...base, category: "message", messageType: "button", safeText: bounded(reply?.title, MAX_SAFE_TEXT), actionId: bounded(reply?.id, MAX_ACTION_ID) };
    }
    if (subtype === "list_reply") {
      const reply = interactive?.list_reply as Record<string, unknown> | undefined;
      return { ...base, category: "message", messageType: "list", safeText: bounded(reply?.title, MAX_SAFE_TEXT), actionId: bounded(reply?.id, MAX_ACTION_ID) };
    }
    if (subtype === "nfm_reply") {
      const reply = interactive?.nfm_reply as Record<string, unknown> | undefined;
      let response: Record<string, unknown> = {};
      try {
        const raw = reply?.response_json;
        response = typeof raw === "string" ? JSON.parse(raw) : ((raw as Record<string, unknown>) ?? {});
      } catch {
        response = {};
      }
      const correlationKey = bounded(response.flow_token, MAX_CORRELATION);
      const redactedResponse: Record<string, unknown> = {};
      for (const key of ["full_name", "age", "gender", "highest_qualification", "course_trade_specialization", "state", "district", "current_village_city", "experience_status", "interview_available"]) {
        const value = bounded(response[key], 200);
        if (value) redactedResponse[key] = value;
      }
      return { ...base, category: "flow", messageType: "flow", actionId: bounded(reply?.name, MAX_ACTION_ID), correlationKey, redactedResponse };
    }
    return { ...base, category: "message", messageType: "unsupported", safeText: subtype ? `Unsupported interactive type: ${subtype}` : "Unsupported interactive message" };
  }
  return { ...base, category: "message", messageType: rawType === "unknown" ? "unknown" : "unsupported" };
}

function parseStatus(status: Record<string, unknown>): NormalizedWebhookEvent | null {
  const id = bounded(status.id, 240);
  const state = bounded(status.status, 40)?.toLowerCase();
  if (!id || !state || !["sent", "delivered", "read", "failed"].includes(state)) return null;
  const providerTimestamp = timestamp(status.timestamp);
  const errors = Array.isArray(status.errors) ? status.errors : [];
  const error = errors[0] as Record<string, unknown> | undefined;
  return {
    providerEventKey: `status:${id}:${state}:${providerTimestamp ?? "unknown"}`,
    category: "message_status",
    providerMessageId: id,
    providerTimestamp,
    status: state as "sent" | "delivered" | "read" | "failed",
    errorCategory: bounded(error?.title, 80),
    errorCode: bounded(error?.code == null ? undefined : String(error.code), 120),
  };
}

export function parseWhatsAppWebhook(payload: unknown): NormalizedWebhookEvent[] {
  if (!payload || typeof payload !== "object") return [];
  const root = payload as Record<string, unknown>;
  if (root.object !== "whatsapp_business_account" || !Array.isArray(root.entry)) return [];
  const events: NormalizedWebhookEvent[] = [];
  for (const entry of root.entry) {
    if (!entry || typeof entry !== "object") continue;
    const changes = (entry as Record<string, unknown>).changes;
    if (!Array.isArray(changes)) continue;
    for (const change of changes) {
      const value = (change as Record<string, unknown>)?.value as Record<string, unknown> | undefined;
      if (!value) continue;
      if (Array.isArray(value.messages)) {
        for (const message of value.messages) {
          const event = parseMessage(message as Record<string, unknown>);
          if (event) events.push(event);
        }
      }
      if (Array.isArray(value.statuses)) {
        for (const status of value.statuses) {
          const event = parseStatus(status as Record<string, unknown>);
          if (event) events.push(event);
        }
      }
    }
  }
  return events;
}

export function summarizeEvent(event: NormalizedWebhookEvent): Record<string, unknown> {
  const summary: Record<string, unknown> = { provider_message_id: event.providerMessageId, provider_timestamp: event.providerTimestamp };
  if (event.messageType) summary.message_type = event.messageType;
  if (event.status) summary.status = event.status;
  if (event.actionId) summary.action_id = event.actionId;
  if (event.errorCategory) summary.error_category = event.errorCategory;
  if (event.errorCode) summary.error_code = event.errorCode;
  return Object.fromEntries(Object.entries(summary).filter(([, value]) => value !== undefined));
}

export function categoryForEmptyEnvelope(): WhatsAppEventCategory {
  return "unknown";
}
