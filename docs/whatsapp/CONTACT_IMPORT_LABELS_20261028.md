# Re-import and saved contact list/tag selectors

Re-importing a contact removed from Contacts now clears the archive marker only for the explicitly imported identity. Excel/CSV and numbers-only imports report added, reused and restored counts, retain the original identity and preserve consent, STOP/suppression, saved labels, subscriptions and message history. Invalid batches roll back restoration. No previously removed contact is restored merely by installing this migration.

Contacts filters and Campaign setup use native dropdowns populated by an Admin-only `admin_console_contact_labels()` RPC. The RPC derives distinct sorted labels across all active contact pages, excludes archived contacts and exposes no names or phone numbers. Organize Selected Contacts includes saved-label selectors plus inputs for new list/tag names. Saving labels reloads the dropdowns and displays confirmation. Changing campaign filters clears previous audience selections. Failed label loading blocks recipient queries and displays a warning instead of silently broadening the audience.

Import clears old list/tag filters and stale selection before reloading Contacts. This prevents successful imports from appearing empty due to a previous filter. Import grants no consent and sends no messages. STOP contacts can reappear in Contacts after an explicit import but remain ineligible for campaigns.

## Release

Apply `20261028062609_restore_imported_contacts_and_label_options.sql` before the updated frontend. It replaces only the verified import function bodies and adds one restricted read-only labels RPC. Existing identities and consent/history fields are preserved. Build from the reviewed branch using the established allowlisted Pages workflow. Do not restore all removed contacts or use real contacts for a deployment smoke test.

Validation includes PGlite runtime tests for both import paths, exact restoration scope, invalid-batch rollback, STOP/history/label preservation, cross-page label discovery and grants; UI tests cover saved-label selection, filters, Campaign query arguments, both import flows and label-load failure. Full suite and artifact validation are required before release. No real data was imported or sent during implementation.
