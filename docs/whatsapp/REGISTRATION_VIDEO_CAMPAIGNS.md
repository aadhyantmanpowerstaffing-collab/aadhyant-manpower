# Registration video campaigns

The existing job-video sender requires a canonical published vacancy and a generated, current job Reel. It cannot use a standalone registration advertisement. The registration video flow adds an explicit fixed Hindi registration contract without inventing a vacancy, Candidate, parallel campaign, or queue.

## Operator workflow

WhatsApp Manager → Campaigns → Registration Video Campaign. Upload an MP4 (100 bytes to 16,000,000 bytes), choose the saved video and preview it privately. Choose the intended contact List/Tag. The fixed Hindi message includes free registration, no candidate job fee, the business telephone, a static Register Now URL button and STOP.

If the template is missing, choose the uploaded review video and use Submit Registration Video Template to Meta. This uploads that video to Meta as a review sample and submits only `aadhyant_registration_video_hi_v1` (`hi`, `MARKETING`). It does not send a message. An existing exact template is reused; mismatches stop, and an ambiguous create is not retried in the same invocation. Sync Meta Approval after Meta approves it. The downloadable request is an alternative for manual setup; its placeholder sample handle must be replaced with an actual Meta-uploaded video sample.

Choose Recipients stays blocked until the exact VIDEO-header/body/buttons contract is approved and freshly synced. Select only eligible contacts (up to 500), preview and Save Campaign for Approval. Approval and Send Now remain distinct operator actions. No send is triggered by upload, setup, saving, deployment or visiting the page.

## Data and sending boundaries

Private bucket `whatsapp-campaign-media`, private immutable media metadata and an optional campaign media foreign key extend the existing canonical campaigns. Job campaigns must retain a non-null job and no promotion media. Only the fixed registration template can use a null job, with a media identity and selected_contacts audience. The canonical vacancy_campaign marketing purpose is retained so both the existing claim and final provider boundary invoke the authoritative send guard.

The promotion guard binds the campaign, recipient, contact, destination, exact variables, approved template snapshot, consent, active profile and unarchived contact at preparation/approval/queue/claim and final provider boundary. It preserves suppression, STOP, sender freshness, leases, existing delivery reports and ambiguous-provider no-retry behavior. Campaign history is preserved; the reports use a left job join to include legitimate jobless promotion campaigns. Other campaigns and automatic alerts keep their existing paths.

Only authenticated Admins can upload, preview, select and prepare. Storage and metadata writes go through the authenticated Edge function with server-side credentials. Browser direct-table/storage writes are not granted. Private media is signed shortly before sending and does not enter audit/template variables or report output. Existing job media remains in its original bucket. Real sending and Meta configuration are separate operator actions and were not exercised during validation.

## Rollout and rollback

Apply `20261028090000_registration_video_campaign.sql`, deploy `whatsapp-campaign-media`, `whatsapp-registration-video-template` and the reviewed `whatsapp-outbox-worker`, then publish the Admin JS. All functions authenticate inside their bodies; gateway JWT verification is disabled consistently with the existing ES256/public-key deployment. New sender behavior is unreachable until an approved template and explicit operator-created, approved, queued promotion exist. Roll back the UI and worker to stop new promotion creation/sending while retaining schema, media and delivery history. Do not replay or delete live outbox rows.

Validation covers exact template matching, private bounded uploads, Admin denial, no fake vacancy, idempotency, missing consent, STOP, archival, changed audiences, failed approval, signed bucket selection, lease identity, final boundary rejection, setup ambiguity and UI no-send behavior. Synthetic fixtures run locally and do not contact candidates or Meta.
