# Saved MP4 videos in manual job campaigns

## Purpose

Aadhyant Admins can upload a reusable MP4 into the existing private `whatsapp-campaign-media` bucket, preview it, and select it for a manual published-job WhatsApp campaign. An uploaded video is not an automatic Job Reel and cannot be published as a public homepage asset. The TATA PV/EV apprenticeship Hindi MP4 is an example; it is **not** included in Git or uploaded to Supabase by this change.

## Admin flow

1. WhatsApp Manager → Campaigns → Saved Videos: choose MP4 (100 bytes–16 MB); upload and privately preview.
2. Create Campaign → published job → current Meta-approved `aadhyant_registered_job_video_hi_v1` or English counterpart → Load Saved MP4s → choose/preview.
3. Choose eligible, opted-in recipients; preview the canonical job details and attached video; Save Campaign for Approval.
4. Separately approve, then explicitly send or schedule. Existing consent, STOP, recipient suppression, contact resolution, idempotency, outbox claim, final send guard, delivery tracking and cancellation remain authoritative. Upload/preparation does not send.

## Architecture

- Reuse `whatsapp-campaign-media`, `private.whatsapp_console_media`, `whatsapp-campaign-media` Edge upload/preview, and the existing job/recipient/campaign/outbox tables.
- Read-only Admin validation: `admin_console_preview_saved_job_video`.
- Preparation: `admin_console_prepare_saved_job_video` reuses the pre-manual-video canonical job campaign preparation function; stores immutable media ID and canonical job-variable snapshot in `whatsapp_campaigns.criteria`.
- Custom video campaigns have a separate `private.console_template_valid` branch because generated Reel existence is not appropriate for uploaded media. That branch checks published job eligibility, fresh compatible VIDEO template, exact template snapshot, media identity/format/size and unchanged canonical job variables.
- The existing manual-video eligibility guard still checks approved/queued state, marketing consent, recipient identity, suppression, exact outbound variables and template. The claimed-media RPC only releases an uploaded media bucket marker for a still-eligible claimed outbox row with the matching lease. The worker strips only the fixed prefix and validates the UUID-shaped private object path before HEAD and short-lived signing.
- Generated job Reels and registration promotion campaigns retain their original routing and handling.

## Deployment order and hold points

1. Review SQL migration `20261105043000_saved_video_job_preview.sql` and `20261105044500_saved_job_video_campaign_binding.sql` against the current **production** schema without modifying it.
2. Execute focused and full tests against an explicitly approved NONPROD environment; verify existing generated video/image/registration campaign regressions.
3. Deploy reviewed migrations before publishing the updated Admin JS or worker helper. Missing migrations should cause Admin preview/prepare to fail, not allow a send.
4. Review the private bucket's MIME/size/CORS configuration and Media URL signing for both direct Meta and WANotifier routes. Check provider-facing payload for a real approved VIDEO header.
5. Only after explicit production approval, deploy and separately upload the owner-provided TATA MP4 through an authenticated Admin session; inspect the preview and select the right published PV/EV vacancy.
6. Use only an explicitly approved test recipient first; obtain separate consent/approval before a real bulk campaign.

## Status

This is an implementation PR, **not a production deployment**. Local SQL runtime/regression tests and real provider end-to-end tests have not been executed in this chat environment. Production data, contacts, queued campaigns and Meta configuration were not mutated; no message was sent. Test and review before merge.
