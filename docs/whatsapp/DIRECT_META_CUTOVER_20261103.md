# Direct Meta cutover — 3 November 2026

The requested provider is direct Meta Cloud API. Production inspection found that the console still dispatches campaigns through `wanotifier-campaign`, operator replies select WANotifier through a runtime flag, and the canonical sender configuration still points at the previous account.

## Prepared source

- Campaign dispatch uses the existing `whatsapp-outbox-worker` and canonical outbox.
- Direct Meta payloads now support English/Hindi selected-vacancy Interested/STOP quick replies and the Hindi image job template.
- Image/video signing reuses the existing leased-media validator; no new tables or alternative outbox are introduced.
- Authorization, consent, final provider boundaries, durable receipts, and ambiguous-outcome reconciliation remain enforced.

## Verified target

- Production project: `wsuctjhbqiedttfnwjvf`.
- Messaging account: `1386833723249335`, owned by Aadhyant Manpower & Staffing.
- Phone number ID: `1415347881659158`; sender: `+919624453543`.
- Existing Employee system user: `61592522723116`; app: `2181424935760142` (Aadhyant Staffing).
- Full access to the target messaging account was explicitly approved and assigned. No new token was generated in this run.

## Remaining production sequence (requires explicit approval)

1. Prepare a Meta app token with only the required WhatsApp management/messaging scopes and a reviewed expiry. Save it only to this production project's encrypted `WHATSAPP_ACCESS_TOKEN`; never print or commit its value.
2. Stop WANotifier dispatch and operator reply paths, including its approved scheduler, before switching sender identities. Preserve historical receipts and ambiguous sends; never replay old campaigns.
3. Update `WHATSAPP_PHONE_NUMBER_ID` and `WHATSAPP_BUSINESS_ACCOUNT_ID` to the target above. Keep automatic sending disabled during validation.
4. Deploy the reviewed worker and frontend artifact through the repository's existing production workflow. Verify sender ownership through Meta before persisting the canonical sender identity.
5. Sync the target account's approved templates. Confirm exact body/button compatibility; do not copy approval state from another account.
6. Check the app subscription and Meta webhook signature/ingress for the target account. Verify incoming text, exact Interested correlation, STOP, and receipt events.
7. Perform only the explicitly approved single-recipient test through the canonical outbox. Confirm provider ID and delivery independently; an accepted send is not proof of delivery.
8. Review interview/recruitment automated dispatch separately before enabling it. The prepared source change routes manual campaigns only; it does not claim that every automation has migrated.

Production secrets, sender records, webhook configuration, runtime flags, and sending were not changed by this source preparation.
