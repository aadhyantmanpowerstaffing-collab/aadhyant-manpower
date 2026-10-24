# Job Reel WhatsApp delivery

Extends the canonical automatic registered-job campaign and outbox. One approved English template contains the generated Hindi video, ten job-summary fields, View Job & Apply, and Stop alerts. No new contact queue or direct-send service is introduced.

Installation defaults to paused. No historical campaign or message is converted or replayed. Once enabled, future regular job publications wait for a ready, current canonical job Reel and a fresh approved, exact VIDEO-header template. The normal automatic worker retries pending publication preparation. Same-Day Pay retains its Hindi text contract. Existing text campaigns retain their original behavior.

Only Reels generated from canonical portal jobs are eligible. Standalone Job details Reels have no canonical vacancy or application target and are excluded. Operator-selected video campaigns are also rejected until explicitly implemented.

The campaign freezes the Reel identity. Claim, media access and final provider checks recheck canonical eligibility, job fingerprint, marketing consent, suppression and exact template approval. Private media is signed for one hour immediately before the provider boundary; only MP4 under 16,000,000 bytes is accepted. Provider ambiguity retains the established reconciliation behavior. Signed links never enter template variables, reports, or audit metadata. Existing immutable rendering supplies H.264/AAC output.

## Deployment and activation

Follow AGENTS.md production approval requirements. Deploy migration `20261024160504_whatsapp_job_reel_delivery.sql` and the changed `whatsapp-outbox-worker` together, initially paused. Refresh actual Meta template metadata through the existing sync; do not fabricate approval. At inspection on 24 October 2026, `aadhyant_registered_job_video_en_v1` was PENDING in the production catalog (last sync 15:50 UTC).

After approval, verify the exact template and a controlled operator-owned test before activating real delivery. An authenticated Admin can call `admin_set_reel_whatsapp_delivery(true)`; it requires fresh compatible approval, active Reel service and an active verified automatic sender. Set false to pause new video deliveries; this also blocks pending video sends. Production deployment, activation and candidate contact require the applicable explicit authorization.

Rollback: pause video delivery and retain canonical outbox, campaigns and media history. Do not delete records or automatically replay prior text alerts. A template/body/size mismatch stops sending rather than silently omitting the video.

## Separate Hindi message variant

`aadhyant_registered_job_video_hi_v1` uses language `hi`, the same Hindi-narrated canonical Reel, Hindi message headings and instructions, a Hindi application button, and a Hindi stop button whose payload remains `STOP`. The exact reviewed template is in `docs/whatsapp/registered-job-video-template-hi-v1.json`; upload a current job Reel as its review-only VIDEO sample. Company names and canonical job values are retained as provided rather than silently translated or inferred.

Migration `20261024162733_hindi_whatsapp_job_reel.sql` adds the separate contract and language selection. It preserves the existing language (`en`) and paused delivery state on installation. While delivery is paused, an authenticated Admin selects `admin_set_reel_whatsapp_language('hi')` or `'en'`. Activating still requires fresh exact approval for that chosen language. This selects one variant for future campaigns; it never sends duplicate English and Hindi alerts to the same recipient or rewrites existing campaigns.

On 24 October 2026 the Hindi template editor was populated in the correct Meta account, but sample-upload browser failure prevented confirmation of submission. Do not describe the Hindi template as submitted or approved until Meta lookup verifies it by exact name and language. Existing English video template remains in review.
