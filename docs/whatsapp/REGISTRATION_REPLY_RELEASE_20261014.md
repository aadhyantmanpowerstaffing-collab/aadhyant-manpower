# Registration reply production release — 14 October 2026

User explicitly approved the prepared database, webhook and site release at 14:27:50 IST on 14 October 2026.

- Reviewed source: bf0ace8b51a409ec9debdfc58dd248560357bd1d.
- Local source commit: 4dd8af7; remote source has the same tree 0bd3176e43397f71d6367da2b7702d3fb0b55558.
- Production migration ledger: 20261014085829 / whatsapp_interested_registration_reply.
- Signed webhook v19 ACTIVE, verify_jwt=false, archive hash ad646e8809bcefb5b48a51c4ddfddeb64aeac59dd4d72d4e99bd3c026dd922c2.
- Downloaded runtime entrypoint and every runtime dependency match reviewed local source exactly.
- Reply claim and provider-boundary RPCs are service-only. Anonymous claim and authenticated boundary execution are denied.
- Sender remains ready; scheduling remains disabled.
- Publishing trigger: aa3db711c3d2011b6d832a405a43f3c84421b45e.
- Successful Pages run: 38539327629; publish job: 115769891284. Immutable source checkout, test/build/verify, upload and publication all succeeded.
- Full local regression: 433 passed, zero failed/skipped; CI build/test/verify succeeded.
- Verified production artifact digest: 7266473e52d3bf9d2cf6e388cc4c0ae53a0fe71e4ecc95c6ae572b776a3a88ed.
- Live Admin console SHA-256: 509581a2edc4978d2774db206f513e068742c4a7f2d882f3d4d533b8277e5669, exactly matching reviewed source.
- Unsigned live webhook POST is rejected as Invalid signature; no ingress or send is authorized.
- Post-deployment read-only verification found zero interested_registration outbox rows. No historical reply replay, backfill, real send, bulk campaign, consent update or Meta configuration change was performed.
- Remove the temporary publisher after successful publication; its removal does not publish another artifact.

The next operator-controlled validation is a fresh Interested button click on the already-delivered test message. The signed event can create at most one registration link through the canonical outbox for that original message. The link directs to Candidate registration with the selected Requirement code; already-account holders can sign in and explicitly Apply. Future alert subscription remains separate and is never inferred from Interested.

This release supersedes the no-automatic-registration-message limitation in SENDER_RELEASE_20261013.md. Existing Candidate/Application, marketing permission and STOP contracts remain authoritative.
