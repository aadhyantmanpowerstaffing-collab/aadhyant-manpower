# Sender and replies deployment — 13 October 2026

This supersedes the historical retired-endpoint status in earlier console checkpoints.

- Authorized task: user selected “sending and replies” and requested “KARI AAPO”.
- Reviewed source: 6f12a51db67787c642d1dfa4ad99416c660c08dd.
- Trigger: 73826b0e34c91ac12ff974d639afdcd1ece8b8cb.
- Successful GitHub Pages run: 38394369586; job 115285719537, all build/test/upload/publish steps successful.
- CI: 416 passed, zero failed. Artifact digest 0ea50f8ea9210835556769b73cdeed598e48ec92fb15e61503b4ebe8419cfa80 matches the local verified build.
- Database migration ledger: 20261013115842 / whatsapp_console_sender.
- Worker v17 and signed webhook v18 ACTIVE, gateway JWT disabled because each implements its own authentication. Sender-setup v1 ACTIVE with gateway JWT required plus admin authorization.
- Live negative endpoint checks: worker returns 401 for missing admin session; setup returns 401 for missing auth header; webhook returns 403 for an unsigned body. These checks persist no inbound or outbox record and cannot send.
- Setup is operator controlled: Admin → WhatsApp Manager → Templates → Verify Sender Connection. It reads Meta phone ownership and required secrets, then stores verified identity; it sends nothing.
- Meta callback remains https://wsuctjhbqiedttfnwjvf.supabase.co/functions/v1/whatsapp-webhook. No real Meta production configuration was changed by this release.
- Scheduling automation remains disabled. Future Schedule queueing refuses until its separate background integration is operational.
- Replies for registered candidates delegate canonical application creation. Imported contact interest is marked registration required; no automatic form message or Candidate creation.
- No real WhatsApp send/test or candidate contact was performed. Actual messaging permission/billing, signed inbound delivery and real message delivery remain unproven pending an explicitly authorized operator-controlled test.
- Remove the one-shot publisher after success; this cleanup publishes no additional artifact.
