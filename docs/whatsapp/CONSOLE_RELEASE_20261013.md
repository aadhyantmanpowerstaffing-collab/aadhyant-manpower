# WhatsApp console production release — 13 October 2026

This supersedes the pending-publication status in CONSOLE_20261013.md.

- User explicitly approved publication of Contacts, Templates, Campaigns and Reports at 16:55 IST.
- The production branch advanced to release trigger 07b46657048461ab1bfe3ae57e1a6953435a0e54.
- Source pinned by checkout: c7fa78e18ad237613ab852f6aec0a0e26fd6525f.
- GitHub Pages run 38390165830, job 115271713394: all steps completed successfully, including deployment.
- Full CI tests: 378 passed, 0 failed. Deterministic artifact digest: 7955c4b2506c2552918c9fc027335448634aec74679ae5687677a2a651958bf2, matching the local verified build.
- Admin entry: https://aadhyantmanpower.in/admin/#whatsappConsole
- Legacy purge verified all seven WhatsApp tables and WhatsApp audit rows empty before installation.
- Backend migration ledger: 20261013112018 / whatsapp_campaign_console. Template-sync Edge version 1 deployed with JWT verification.
- All 14 admin console RPCs are SECURITY DEFINER with empty search_path. Anon has no console contact access; template sync is service-role-only.
- Sender readiness remains false. Retired worker and webhook remain unchanged; scheduler remains disabled. No real recipient was contacted or queued.
- Meta sync requires an authenticated admin session and configured server credentials. Live Meta sync and sender restoration remain outstanding.
- Authenticated visual/browser QA has not been performed. This release proves successful build/deployment, not live delivery.
- Remove the one-shot publication helper after successful deployment. No new site publication is caused by this proof-only cleanup.
