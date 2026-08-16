# Reconstruction R3 — Reference Data

## Status

R3 is blocked at the required India State/District dataset boundary. Repository inspection found no local JSON, CSV, GeoJSON, JavaScript, or other complete location dataset. The task prohibits fabricating incomplete State/District data and prohibits external downloading or package installation.

No reference dataset was populated, no component was connected to a production form, and no demo was created using partial data.

## Dataset and canonical-code contract

`assets/data/README.md` defines the required common record, stable-code rules, location parent relationship, planned files, provenance requirements, duplicate rules, retirement behavior, and historical-value compatibility.

Location codes use a stable country/subdivision namespace such as `IN_GJ`. District records use unique stable codes and an explicit `stateCode` foreign-key-like relationship. Labels remain presentation values and may change without changing identity.

## State to District behavior

When an approved complete dataset becomes available, the reusable location component must:

1. Load States and Districts through the shared reference-data loader.
2. Render canonical active States in configured sort order.
3. Keep District disabled until a State is selected.
4. Filter Districts by exact `stateCode`.
5. Clear the District value whenever State changes.
6. Preserve accessible labels, descriptions, disabled state, keyboard operation, and native mobile behavior.
7. Provide lightweight type-ahead filtering without introducing a third-party dependency.

## Education dependencies

The approved model must include the requested Education codes and map dependencies explicitly:

- ITI → ITI Trades
- Diploma → Diploma Branches
- B.E./B.Tech → Engineering Branches
- Graduate/Post Graduate → approved Degree/Course options
- Other → bounded free-text input
- School-level qualifications → no dependent control

Changing Education must clear any incompatible dependent code and free-text value. Arrays must live in shared datasets, never individual forms.

## Historical-data compatibility

R3 performs no database normalization. Future integrations must distinguish canonical codes from historical labels, retain display fallback for legacy free text, and adapt submissions to each unchanged Supabase contract. A schema migration may be proposed only in a later separately authorized database phase.

## Required source approval

To unblock R3, supply or approve a complete, attributable India administrative dataset that includes every current State and Union Territory and its District relationships. Before import, verify coverage, provenance, date/version, usage rights, canonical spelling, duplicates, and orphan parents.

## Tests pending data availability

Once data is approved, validation must cover JSON parsing, schemas, duplicate codes and labels, orphan districts, dependency integrity, required education relationships, native keyboard behavior, State reset behavior, responsive widths 360/390/768/1024/1440, and zero unexplained browser errors or failed requests.

No SQL, Supabase, portal, configuration, CNAME, favicon, commit, push, merge, deployment, or production action occurred.
