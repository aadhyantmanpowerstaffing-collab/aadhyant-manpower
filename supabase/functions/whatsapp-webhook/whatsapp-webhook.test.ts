import assert from "node:assert/strict";
import test from "node:test";
import { FakeProviderError, FakeWhatsAppProvider } from "../_shared/whatsapp/fake-provider.ts";
import { parseWhatsAppWebhook } from "../_shared/whatsapp/parser.ts";
import { normalizeIndianWhatsAppPhone } from "../_shared/whatsapp/phone.ts";
import { calculateMetaSignature, verifyMetaSignature } from "../_shared/whatsapp/signature.ts";
import type { AcceptedWebhookEvent, WebhookEnvironment } from "../_shared/whatsapp/types.ts";
import { handleWhatsAppWebhook } from "./index.ts";

const encoder = new TextEncoder();
const environment: WebhookEnvironment = { appSecret: "unit-test-secret", verifyToken: "unit-test-verify", supabaseUrl: "https://nonprod.invalid", supabaseSecretKey: "not-used" };
const envelope = (value: Record<string, unknown>) => ({ object: "whatsapp_business_account", entry: [{ changes: [{ field: "messages", value }] }] });
const signedRequest = async (payload: unknown, overrides: { body?: string; signature?: string | null; contentType?: string } = {}) => {
  const body = overrides.body ?? JSON.stringify(payload);
  const signature = overrides.signature === undefined ? await calculateMetaSignature(encoder.encode(body), environment.appSecret) : overrides.signature;
  const headers = new Headers({ "content-type": overrides.contentType ?? "application/json" });
  if (signature !== null) headers.set("x-hub-signature-256", signature);
  return new Request("https://nonprod.invalid/whatsapp-webhook", { method: "POST", headers, body });
};

test("GET verification accepts only the exact token and challenge", async () => {
  const accepted: AcceptedWebhookEvent[] = [];
  const valid = await handleWhatsAppWebhook(new Request("https://x.test/?hub.mode=subscribe&hub.verify_token=unit-test-verify&hub.challenge=42"), environment, async (event) => { accepted.push(event); });
  assert.equal(valid.status, 200); assert.equal(await valid.text(), "42"); assert.equal(accepted.length, 0);
  for (const url of ["https://x.test/?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=42", "https://x.test/?hub.mode=subscribe&hub.challenge=42"]) {
    assert.equal((await handleWhatsAppWebhook(new Request(url), environment, async () => {})).status, 403);
  }
});

test("signature verification is raw-body exact and fails closed", async () => {
  const raw = encoder.encode('{"a":1}');
  const signature = await calculateMetaSignature(raw, environment.appSecret);
  assert.equal(await verifyMetaSignature(raw, signature, environment.appSecret), true);
  assert.equal(await verifyMetaSignature(encoder.encode('{"a": 1}'), signature, environment.appSecret), false);
  assert.equal(await verifyMetaSignature(raw, signature, "wrong"), false);
  assert.equal(await verifyMetaSignature(raw, null, environment.appSecret), false);
});

test("POST rejects missing or invalid signature before accepting events", async () => {
  const payload = envelope({ messages: [{ id: "wamid.1", from: "919876543210", timestamp: "1720000000", type: "text", text: { body: "Hello" } }] });
  for (const signature of [null, "sha256=bad"]) {
    const accepted: AcceptedWebhookEvent[] = [];
    const result = await handleWhatsAppWebhook(await signedRequest(payload, { signature }), environment, async (event) => { accepted.push(event); });
    assert.equal(result.status, 403); assert.equal(accepted.length, 0);
  }
});

test("POST validates content type, size and JSON only after signature", async () => {
  assert.equal((await handleWhatsAppWebhook(await signedRequest({}, { contentType: "text/plain" }), environment, async () => {})).status, 415);
  const invalid = await signedRequest({}, { body: "{" });
  assert.equal((await handleWhatsAppWebhook(invalid, environment, async () => {})).status, 400);
  const oversizedBody = JSON.stringify({ value: "x".repeat(1_048_576) });
  assert.equal((await handleWhatsAppWebhook(await signedRequest({}, { body: oversizedBody }), environment, async () => {})).status, 413);
});

test("parser normalizes text, button, list, Flow and multi-event envelopes", () => {
  const payload = envelope({ messages: [
    { id: "m1", from: "919876543210", timestamp: "1720000000", type: "text", text: { body: "Hello" } },
    { id: "m2", from: "919876543210", type: "interactive", interactive: { type: "button_reply", button_reply: { id: "INTERESTED", title: "Interested" } } },
    { id: "m3", from: "919876543210", type: "interactive", interactive: { type: "list_reply", list_reply: { id: "VIEW_JOB", title: "View job" } } },
    { id: "m4", from: "919876543210", type: "interactive", interactive: { type: "nfm_reply", nfm_reply: { name: "flow", response_json: JSON.stringify({ flow_token: "opaque", full_name: "Synthetic User", aadhaar: "must-not-copy" }) } } },
  ] });
  const events = parseWhatsAppWebhook(payload);
  assert.deepEqual(events.map((event) => event.messageType), ["text", "button", "list", "flow"]);
  assert.equal(events[3].redactedResponse?.full_name, "Synthetic User");
  assert.equal("aadhaar" in (events[3].redactedResponse ?? {}), false);
  assert.equal(new Set(events.map((event) => event.providerEventKey)).size, 4);
});

test("parser normalizes status events and safely ignores unknown envelopes", () => {
  const statuses = parseWhatsAppWebhook(envelope({ statuses: [
    { id: "w1", status: "sent", timestamp: "1720000000" }, { id: "w1", status: "delivered", timestamp: "1720000001" },
    { id: "w1", status: "read", timestamp: "1720000002" }, { id: "w2", status: "failed", timestamp: "1720000003", errors: [{ code: 131000, title: "Safe category" }] },
  ] }));
  assert.deepEqual(statuses.map((event) => event.status), ["sent", "delivered", "read", "failed"]);
  assert.deepEqual(parseWhatsAppWebhook({ object: "unknown" }), []);
});

test("valid POST durably submits normalized event summaries and duplicates retain a stable key", async () => {
  const payload = envelope({ messages: [{ id: "wamid.same", from: "919876543210", type: "text", text: { body: "Private body is not included in ledger summary" } }] });
  const accepted: AcceptedWebhookEvent[] = [];
  const request = await signedRequest(payload);
  const result = await handleWhatsAppWebhook(request, environment, async (event) => { accepted.push(event); });
  assert.equal(result.status, 200); assert.equal(accepted.length, 1); assert.equal(accepted[0].provider_event_key, "message:wamid.same");
  assert.equal(JSON.stringify(accepted[0]).includes("Private body"), false);
  assert.equal(accepted[0].payload_sha256.length, 64);
});

test("phone normalization accepts canonical Indian forms and rejects invalid values", () => {
  for (const value of ["9876543210", "919876543210", "+91 98765 43210"]) {
    assert.deepEqual(normalizeIndianWhatsAppPhone(value), { indianMobileKey: "9876543210", providerAddress: "+919876543210" });
  }
  for (const value of ["", "1234567890", "+1 9876543210", "91987654321"]) assert.throws(() => normalizeIndianWhatsAppPhone(value));
});

test("fake provider returns deterministic safe outcomes without external calls", async () => {
  const request = { destination: "+919876543210", templateName: "test", templateLanguage: "en", templateVersion: "1", variables: {}, idempotencyKey: "id-1" };
  assert.equal((await new FakeWhatsAppProvider("success").sendTemplate(request)).providerMessageId, "fake-id-1");
  for (const outcome of ["transient", "permanent", "ambiguous"] as const) {
    const provider = new FakeWhatsAppProvider(outcome);
    await assert.rejects(() => provider.sendTemplate(request), FakeProviderError);
    const classified = provider.classifyError(new FakeProviderError(outcome));
    assert.equal(classified.kind, outcome); assert.equal(JSON.stringify(classified).includes("secret"), false);
  }
});

test("webhook implementation contains no recruitment mutation or Graph send path", async () => {
  const source = await import("node:fs/promises").then((fs) => fs.readFile(new URL("./index.ts", import.meta.url), "utf8"));
  assert.doesNotMatch(source, /candidate_applications|create_candidate|graph\.facebook|send_template/i);
  assert.doesNotMatch(source, /console\.(?:log|error).*secret/i);
});
