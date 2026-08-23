export type WhatsAppEventCategory = "message" | "message_status" | "flow" | "unknown";

export type NormalizedWebhookEvent = {
  providerEventKey: string;
  category: WhatsAppEventCategory;
  providerMessageId?: string;
  providerTimestamp?: string;
  phone?: string;
  messageType?: "text" | "button" | "list" | "flow" | "unsupported" | "unknown";
  safeText?: string;
  actionId?: string;
  correlationKey?: string;
  status?: "sent" | "delivered" | "read" | "failed";
  errorCategory?: string;
  errorCode?: string;
  redactedResponse?: Record<string, unknown>;
};

export type WebhookEnvironment = {
  appSecret: string;
  verifyToken: string;
  supabaseUrl: string;
  supabaseSecretKey: string;
};

export type AcceptedWebhookEvent = {
  provider_event_key: string;
  payload_sha256: string;
  event_category: WhatsAppEventCategory;
  redacted_payload: Record<string, unknown>;
};
