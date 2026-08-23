export type TemplateSendRequest = {
  destination: string;
  templateName: string;
  templateLanguage: string;
  templateVersion: string;
  variables: Record<string, unknown>;
  idempotencyKey: string;
};

export type ProviderSendResult = { providerMessageId: string };
export type ProviderFailureKind = "transient" | "permanent" | "ambiguous";
export type ProviderErrorClassification = { kind: ProviderFailureKind; category: string; code: string };

export interface WhatsAppProvider {
  sendTemplate(request: TemplateSendRequest): Promise<ProviderSendResult>;
  classifyError(error: unknown): ProviderErrorClassification;
  extractProviderMessageId(response: unknown): string;
}
