# Hindi job alert contact line

New operator-selected Hindi job campaigns use the already-approved `aadhyant_registered_job_alert_hi_v2` template. Its exact body includes:

अधिक जानकारी या नौकरी के लिए आवेदन करने हेतु 9586785800 पर कॉल करें।

The portal previously exposed only the supported `hi_v1` sender contract, so successful messages omitted the phone line even though Meta had approved `hi_v2`. This release strictly validates and supports `hi_v2` in catalog sync, canonical selected-campaign queueing, final send eligibility, message payload construction, and preview. Old campaigns keep their original frozen template and are never replayed or rewritten. New campaign choices omit `hi_v1`; the new variant appears only with fresh compatible Meta approval.

Apply the additive migration and deploy the worker plus portal artifact. Refresh Meta templates using the existing sync. Do not mark compatibility/approval by hand. No template submission, new consent, duplicate send, video activation, or automatic-campaign language change is introduced. Existing English, Same-Day Pay, video, STOP and reconciliation behavior remains unchanged.

Validation includes exact-body/phone and header mismatch rejection, canonical ten-field payloads, idempotent queueing, Admin grants, job-change checks, suppression, and the new preview/selection behavior.
