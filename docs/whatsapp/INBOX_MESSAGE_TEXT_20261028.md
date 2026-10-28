# Readable incoming WhatsApp messages — prepared fix

Status: prepared locally; not deployed. This change requires the database migration, webhook deployment and Admin Pages release together. Production approval is still required by AGENTS.md.

The Inbox rendered summaries because the webhook passed `p_safe_text: null`, the canonical recorder discarded its text argument, and the Admin history RPC never projected it. This patch corrects all three stages. Incoming text and button/list labels are bounded to 4096 characters and stored in the existing `whatsapp_inbound_messages.safe_text`. The Admin RPC projects readable text into its existing `summary` field, so the existing text-node renderer preserves Gujarati and line breaks without evaluating HTML.

Existing messages are not backfilled: discarded text cannot be recovered from the summary ledger. History labels this explicitly. Attachments have an explicit unsupported-preview label. Automated outgoing messages keep their existing purpose summaries; operator replies retain their exact existing bodies. This does not implement media downloads or reconstruct sent templates.

Registration answers remain in the existing private registration workflow and are excluded while a chat is active. Flow data and REGCHAT action payloads are never stored as transcript text. Registration-linked history continues to show a neutral notice. The display sanitizer omits messages containing identity/financial/credential keywords, numeric sequences of nine or more digits (including separated digits), and URLs. These conservative patterns can hide legitimate text and are not a general-purpose sensitive-data classifier. The existing raw event ledger remains summary-only. No table grants or public access are added: the recorder remains service-role-only and the history RPC remains guarded Admin-only. Existing RLS remains unchanged.

A failed reply-window lookup no longer prevents history from opening. It displays a retry notice and disables new replies until availability can be verified. Existing server-side authorship, sender verification, STOP, 24-hour reply window, idempotency and once-only delivery checks remain unchanged.

## Release order after approval

1. Verify the production project identity and migration history; preserve live records.
2. Apply `20261028033902_whatsapp_inbox_message_text.sql`.
3. Deploy the matching `whatsapp-webhook` and its shared parser.
4. Publish the matching Admin artifact through the existing production Pages workflow.
5. Verify Admin-only RPC grants and authenticated history. A real inbound/send test requires operator-controlled authorization; do not send to candidates for validation.

If the webhook deploy precedes the migration, text continues to be discarded by the old recorder; those messages cannot be recovered. Keep the migration first. No bulk campaign, consent update, Meta configuration change, real message send, or live database mutation has been performed while preparing this fix.

## Verification

Local focused SQL and DOM coverage checks Gujarati round-trip, 4096-character text, canonical duplicate replay, missing old text, registration and Flow exclusions, sensitive identifiers, recorder grants, Admin denial, safe DOM rendering and readable history when reply availability fails. The existing operator reply suites cover reply-window, STOP, sender, author, reconciliation and duplicate-click behavior. Full regression and production artifact checks are recorded in the final change report.

Final local results: complete regression 718/718 passed, zero failures/skips; final webhook/SQL focused run 27/27 passed; SQL recheck after self-review 2/2 passed; JS syntax, production artifact build, digest verification and `git diff --check` passed. Live authenticated browser/provider verification remains pending deployment approval. Remote code upload was blocked by automatic approval review for lack of explicit external upload authorization; no code payload was published.
