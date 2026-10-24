# Job Reel WhatsApp delivery

Extends the canonical automatic registered-job campaign and outbox. One approved English template contains the generated Hindi video, ten job-summary fields, View Job & Apply, and Stop alerts. No new contact queue or direct-send service is introduced.

Installation defaults to paused. No historical campaign or message is converted or replayed. Once enabled, future regular job publications wait for a ready, current canonical job Reel and a fresh approved, exact VIDEO-header template. The normal automatic worker retries pending publication preparation. Same-Day Pay retains its Hindi text contract. Existing text campaigns retain their original behavior.

Only Reels generated from canonical portal jobs are eligible. Standalone Job details Reels have no canonical vacancy or application target and are excluded. Operator-selected video campaigns are also rejected until explicitly implemented.

The campaign freezes the Reel identity. Claim, media access and final provider checks recheck canonical eligibility, job fingerprint, marketing consent, suppression and exact template approval. Private media is signed for one hour immediately before the provider boundary; only MP4 under 16,000,000 bytes is accepted. Provider ambiguity retains the established reconciliation behavior. Signed links never enter template variables, reports, or audit metadata. Existing immutable rendering supplies H.264/AAC output.

## Deployment and activation

Follow AGENTS.md production approval requirements. Deploy migration `20261024160504_whatsapp_job_reel_delivery.sql` and the changed `whatsapp-outbox-worker` together, initially paused. Refresh actual Meta template metadata through the existing sync; do not fabricate approval. At inspection on 24 October 2026, `aadhyant_registered_job_video_en_v1` was PENDING in the production catalog (last sync 15:50 UTC).

After approval, verify the exact template and a controlled operator-owned test before activating real delivery. An authenticated Admin can call `admin_set_reel_whatsapp_delivery(true)`; it requires fresh compatible approval, active Reel service and an active verified automatic sender. Set false to pause new video deliveries; this also blocks pending video sends. Production deployment, activation and candidate contact require the applicable explicit authorization.

Rollback: pause video delivery and retain canonical outbox, campaigns and media history. Do not delete records or automatically replay prior text alerts. A template/body/size mismatch stops sending rather than silently omitting the video.
