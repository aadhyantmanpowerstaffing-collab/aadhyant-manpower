# Four-step WhatsApp chat registration — 14 October 2026

The user requested the shortest practical chat registration at 17:53:06 IST, after the real test confirmed that individual questions felt too long.

New registrations use four prompts:

1. Separate registration/contact Yes / No.
2. One reply for Name | Age | Gender | State | District | City/Village.
3. One reply for Qualification | Trade/Course | Fresher/Experienced | Interview Yes/No.
4. Separate optional ALL job-alert Yes / No.

Prompts include a short example; each grouped reply also accepts one value per line. Parsing is deterministic, requires exactly six or four values, normalizes supported enums case-insensitively, checks canonical age/length ranges and rejects links, extra/missing fields or invalid values. An invalid group never partially changes stored answers. Completion uses the same canonical Candidate/Application transaction and separate signed consent evidence; no new Auth account or hiring stage is created.

Existing sessions retain legacy prompt semantics, including in-flight replies. New compact sessions are enabled only after the updated webhook is verified. Outbox prompt mode must match the session at the final provider boundary. STOP, CANCEL, RESUME, 24-hour expiry, once-only sends, replay protection and identity-conflict review remain intact.

No real contact, historical response, registration, alert consent or message is replayed as a deployment test. Duplicate Candidate identity remains a staff-review boundary; this change does not merge, delete or choose a profile automatically.

Migration: 20261014122353_whatsapp_compact_chat_registration.sql. The migration adds a default-disabled new-intake feature flag and a legacy default for retained session rows. Activation follows deployment verification.

## Verified release

- Complete local regression: 488 passed, zero failed/skipped, including seven compact database cases and the four-prompt payload test. Existing legacy sessions are tested against the upgraded processor.
- Production migration ledger: 20261014123517 / whatsapp_compact_chat_registration on wsuctjhbqiedttfnwjvf.
- Webhook v23 ACTIVE; archive hash ef38f97d14dc812247893600538c499ab7710ea1bd9f7281e0f7df0999cfee47. Every emitted runtime file exactly matches reviewed source.
- Compact flag enabled only after runtime comparison. Sender verified; unsigned POST returns 403. Browser orchestration execute is denied; the private parser has no anon/authenticated/service-role direct execute.
- One retained legacy review session remains unchanged. Zero compact sessions were fabricated or replayed; no new test message was sent during this change.
- Build/artifact validation passes. This changes server-generated WhatsApp messages; the published site files remain unchanged.
- Real user-device compact intake is not claimed as tested. Existing duplicate-profile cases still need staff identity review.

