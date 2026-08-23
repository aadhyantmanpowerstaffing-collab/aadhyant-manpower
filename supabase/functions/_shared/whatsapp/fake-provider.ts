import type { ProviderErrorClassification, ProviderSendResult, TemplateSendRequest, WhatsAppProvider } from "./provider.ts";

export type FakeOutcome = "success" | "transient" | "permanent" | "ambiguous";

export class FakeProviderError extends Error {
  readonly outcome: Exclude<FakeOutcome, "success">;

  constructor(outcome: Exclude<FakeOutcome, "success">) {
    super(`Fake provider ${outcome} outcome`);
    this.name = "FakeProviderError";
    this.outcome = outcome;
  }
}

export class FakeWhatsAppProvider implements WhatsAppProvider {
  private readonly outcome: FakeOutcome;

  constructor(outcome: FakeOutcome = "success") {
    this.outcome = outcome;
  }

  async sendTemplate(request: TemplateSendRequest): Promise<ProviderSendResult> {
    if (this.outcome !== "success") throw new FakeProviderError(this.outcome);
    return { providerMessageId: `fake-${request.idempotencyKey}` };
  }

  classifyError(error: unknown): ProviderErrorClassification {
    const outcome = error instanceof FakeProviderError ? error.outcome : "permanent";
    return { kind: outcome, category: "fake_provider", code: `fake_${outcome}` };
  }

  extractProviderMessageId(response: unknown): string {
    if (!response || typeof response !== "object") throw new Error("Provider response is invalid");
    const id = (response as Record<string, unknown>).providerMessageId;
    if (typeof id !== "string" || !id) throw new Error("Provider message ID is missing");
    return id;
  }
}
