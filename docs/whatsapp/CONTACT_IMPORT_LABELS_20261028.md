# Re-import and saved contact list/tag selectors

Re-importing a contact removed from Contacts now clears the archive marker only for the explicitly imported identity. Excel/CSV and numbers-only imports report added, reused and restored counts, retain the original identity and preserve consent, STOP/suppression, saved labels, subscriptions and message history. Invalid batches roll back restoration. No previously removed contact is restored merely by installing this migration.

Contacts filters and Campaign setup use native dropdowns populated by an Admin-only `admin_console_contact_labels()` RPC. The RPC derives distinct sorted labels across all active contact pages, excludes archived contacts and exposes no names or phone numbers. Organize Selected Contacts includes saved-label selectors plus inputs for new list/tag names. Saving labels reloads the dropdowns and displays confirmation. Changing campaign filters clears previous audience selections. Failed label loading blocks recipient queries and displays a warning instead of silently broadening the audience.

Import clears old list/tag filters and stale selection before reloading Contacts. This prevents successful imports from appearing empty due to a previous filter. Import grants no consent and sends no messages. STOP contacts can reappear in Contacts after an explicit import but remain ineligible for campaigns.

## Release

Apply `20261028062609_restore_imported_contacts_and_label_options.sql` before the updated frontend. It replaces only the verified import function bodies and adds one restricted read-only labels RPC. Existing identities and consent/history fields are preserved. Build from the reviewed branch using the established allowlisted Pages workflow. Do not restore all removed contacts or use real contacts for a deployment smoke test.

Validation includes PGlite runtime tests for both import paths, exact restoration scope, invalid-batch rollback, STOP/history/label preservation, cross-page label discovery and grants; UI tests cover saved-label selection, filters, Campaign query arguments, both import flows and label-load failure. Full suite and artifact validation are required before release. No real data was imported or sent during implementation.

## Production verification

Released as user-authorized corrections on 28 October 2026. PR #20 merged at `34c89ff0fc1f9286121784acfde2502a620c083d` (tree `d77f3b627006e970d202283d591b4140fe86f66a`). Migration installed as `20261028063238 / restore_imported_contacts_and_label_options` in verified production project `wsuctjhbqiedttfnwjvf`. Previous import function body hashes matched the expected source before replacement.

Local regression passed 732/732; final UI tests passed 9/9 after the filter-clear adjustment. Production workflow `40644930379` passed full regression, artifact checks and deployment (build job `122671417035`, deploy job `122672599532`). Published Admin JavaScript matches reviewed source byte-for-byte, SHA-256 `f5adf6232cb763d1578139cf5a19f2c383a861be655087115058882743971468`.

Read-only post-migration verification retained 875 contacts (zero visible), 14 inbound and 498 outbound rows: installation restored no real contacts and sent no messages. Labels RPC permits authenticated calls with its Admin guard and denies anonymous execution. Advisor reports the expected authenticated SECURITY DEFINER notice for this restricted RPC, with no new anonymous callable endpoint. Operator should refresh and explicitly re-import the required batch; authenticated live import/UI confirmation remains pending to avoid using real contacts as test fixtures.
