import assert from "node:assert/strict";
import test from "node:test";
import { FakeProviderError, FakeWhatsAppProvider } from "../_shared/whatsapp/fake-provider.ts";
import { parseWhatsAppWebhook } from "../_shared/whatsapp/parser.ts";
import { normalizeIndianWhatsAppPhone } from "../_shared/whatsapp/phone.ts";
import { calculateMetaSignature, verifyMetaSignature } from "../_shared/whatsapp/signature.ts";
import type { AcceptedWebhookEvent, WebhookEnvironment } from "../_shared/whatsapp/types.ts";
import { createSupabaseWebhookPersistence, handleWhatsAppWebhook } from "./index.ts";

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
  for (const url of [
    "https://x.test/?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=42",
    "https://x.test/?hub.mode=subscribe&hub.challenge=42",
    "https://x.test/?hub.mode=wrong&hub.verify_token=unit-test-verify&hub.challenge=42",
    "https://x.test/?hub.mode=subscribe&hub.verify_token=unit-test-verify",
  ]) {
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

test("parser skips malformed message and status members while preserving valid siblings", () => {
  const payload = envelope({
    messages: [null, 7, [], { id: "valid-message", from: "919876543210", type: "text", text: { body: "Valid" } }],
    statuses: [null, "bad", [], { id: "valid-status", status: "delivered", timestamp: "1720000001" }],
  });
  const events = parseWhatsAppWebhook(payload);
  assert.deepEqual(events.map((event) => event.providerEventKey), ["message:valid-message", "status:valid-status:delivered:2024-07-03T09:46:41.000Z"]);
});

test("Flow parser safely handles malformed, null and wrong-shape response JSON", () => {
  const flow = (id: string, response_json: unknown) => ({
    id,
    from: "919876543210",
    type: "interactive",
    interactive: { type: "nfm_reply", nfm_reply: { name: "flow", response_json } },
  });
  const events = parseWhatsAppWebhook(envelope({ messages: [flow("f1", "{"), flow("f2", "null"), flow("f3", "[]"), flow("f4", { bank_account: "must-not-copy", full_name: "Safe" })] }));
  assert.equal(events.length, 4);
  assert.deepEqual(events.slice(0, 3).map((event) => event.redactedResponse), [{}, {}, {}]);
  assert.deepEqual(events[3].redactedResponse, { full_name: "Safe" });
  assert.equal(JSON.stringify(events).includes("must-not-copy"), false);
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

test("verified text accepts first, upserts contact and records no raw text", async () => {
  const payload = envelope({ messages: [{ id: "wamid.orchestrated.text", from: "919876543210", timestamp: "1720000000", type: "text", text: { body: "Must not reach persistence" } }] });
  const calls: Array<{ rpc: string; body: Record<string, unknown> }> = [];
  const fetcher = async (input: string | URL | Request, init?: RequestInit): Promise<Response> => {
    const rpc = String(input).split("/").at(-1)!;
    const body = JSON.parse(String(init?.body)) as Record<string, unknown>;
    calls.push({ rpc, body });
    const value = rpc === "accept_whatsapp_webhook_event" ? "00000000-0000-0000-0000-000000000001"
      : rpc === "upsert_whatsapp_inbound_contact" ? "00000000-0000-0000-0000-000000000002"
      : "00000000-0000-0000-0000-000000000003";
    return new Response(JSON.stringify(value), { status: 200, headers: { "content-type": "application/json" } });
  };
  const persistence = createSupabaseWebhookPersistence(environment, fetcher);
  const result = await handleWhatsAppWebhook(await signedRequest(payload), environment, persistence.acceptEvent, persistence.processInboundEvent);
  assert.equal(result.status, 200);
  assert.deepEqual(calls.map((call) => call.rpc), ["accept_whatsapp_webhook_event", "upsert_whatsapp_inbound_contact", "record_whatsapp_inbound_message"]);
  assert.equal(calls[1].body.p_phone, "919876543210");
  assert.equal(calls[2].body.p_message_type, "text");
  assert.equal(calls[2].body.p_safe_text, null);
  assert.equal(JSON.stringify(calls).includes("Must not reach persistence"), false);
});

test("button, list and Flow events use the normalized inbound persistence stage", async () => {
  const cases = [
    { type: "interactive", interactive: { type: "button_reply", button_reply: { id: "YES", title: "Yes" } } },
    { type: "interactive", interactive: { type: "list_reply", list_reply: { id: "VIEW", title: "View" } } },
    { type: "interactive", interactive: { type: "nfm_reply", nfm_reply: { name: "flow", response_json: JSON.stringify({ flow_token: "opaque", full_name: "Safe", bank_account: "blocked" }) } } },
  ];
  const processed: Array<{ webhookEventId: string; event: ReturnType<typeof parseWhatsAppWebhook>[number] }> = [];
  const payload = envelope({ messages: cases.map((message, index) => ({ id: `orchestrated-${index}`, from: "919876543210", ...message })) });
  const result = await handleWhatsAppWebhook(await signedRequest(payload), environment, async () => "00000000-0000-0000-0000-000000000001", async (webhookEventId, event) => { processed.push({ webhookEventId, event }); });
  assert.equal(result.status, 200);
  assert.deepEqual(processed.map(({ event }) => event.messageType), ["button", "list", "flow"]);
  assert.deepEqual(processed[2].event.redactedResponse, { full_name: "Safe" });
  assert.equal(JSON.stringify(processed).includes("blocked"), false);
});

test("exact duplicate replay retains one logical contact and inbound message", async () => {
  const payload = envelope({ messages: [{ id: "wamid.orchestrated.duplicate", from: "919876543210", type: "text", text: { body: "Private" } }] });
  const contacts = new Set<string>();
  const messages = new Set<string>();
  const accept = async () => "00000000-0000-0000-0000-000000000001";
  const process = async (_webhookEventId: string, event: ReturnType<typeof parseWhatsAppWebhook>[number]) => {
    contacts.add(event.phone!);
    messages.add(event.providerMessageId!);
  };
  for (let attempt = 0; attempt < 2; attempt++) {
    assert.equal((await handleWhatsAppWebhook(await signedRequest(payload), environment, accept, process)).status, 200);
  }
  assert.equal(contacts.size, 1);
  assert.equal(messages.size, 1);
});

test("malformed siblings do not block valid inbound orchestration", async () => {
  const payload = envelope({ messages: [null, 7, [], { id: "orchestrated-valid", from: "919876543210", type: "text", text: { body: "Private" } }] });
  const processed: string[] = [];
  const result = await handleWhatsAppWebhook(await signedRequest(payload), environment, async () => "00000000-0000-0000-0000-000000000001", async (_id, event) => { processed.push(event.providerMessageId!); });
  assert.equal(result.status, 200);
  assert.deepEqual(processed, ["orchestrated-valid"]);
});

test("contact persistence failure follows durable acceptance and fails closed", async () => {
  const payload = envelope({ messages: [{ id: "orchestrated-failure", from: "919876543210", type: "text", text: { body: "Private" } }] });
  const order: string[] = [];
  const result = await handleWhatsAppWebhook(await signedRequest(payload), environment, async () => { order.push("accepted"); return "00000000-0000-0000-0000-000000000001"; }, async () => { order.push("contact"); throw new Error("synthetic failure"); });
  assert.equal(result.status, 500);
  assert.equal(await result.text(), "Event processing failed");
  assert.deepEqual(order, ["accepted", "contact"]);
});

test("status events remain ledger-only until separately reviewed orchestration", async () => {
  const payload = envelope({ statuses: [{ id: "status-ledger-only", status: "delivered", timestamp: "1720000001" }] });
  let accepted = 0;
  let inbound = 0;
  const result = await handleWhatsAppWebhook(await signedRequest(payload), environment, async () => { accepted++; return "00000000-0000-0000-0000-000000000001"; }, async () => { inbound++; });
  assert.equal(result.status, 200);
  assert.equal(accepted, 1);
  assert.equal(inbound, 0);
});

test("phone normalization accepts canonical Indian forms and rejects invalid values", () => {
  for (const value of ["9876543210", "919876543210", "+91 98765 43210"]) {
    assert.deepEqual(normalizeIndianWhatsAppPhone(value), { indianMobileKey: "9876543210", providerAddress: "+919876543210" });
  }
  assert.deepEqual(normalizeIndianWhatsAppPhone("+91 98765-43210"), { indianMobileKey: "9876543210", providerAddress: "+919876543210" });
  for (const value of ["", "1234567890", "+1 9876543210", "91987654321", "abc9876543210", "98765abc43210", "98765/43210"]) {
    assert.throws(() => normalizeIndianWhatsAppPhone(value));
  }
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
