# Aadhyant reference-data contract

This directory is the single source for controlled public and portal form options. R3 did not populate datasets because no complete, attributable India State/District source was available locally. Partial or manually reconstructed location data must not be committed here.

## Common option record

Every option dataset uses stable codes rather than presentation labels as identity:

```json
{
  "code": "ITI_FITTER",
  "label": "Fitter",
  "active": true,
  "sortOrder": 10,
  "aliases": []
}
```

Rules:

- `code`: required, unique, uppercase `A-Z0-9_`, and immutable after use.
- `label`: required human-readable English label.
- `active`: required boolean. Retire options instead of deleting codes used by records.
- `sortOrder`: required non-negative integer.
- `aliases`: optional historical/search labels; never used as identity.
- Dataset files contain a JSON array of records.
- Duplicate codes are forbidden globally within each dataset.
- Duplicate case-insensitive labels are forbidden within a dataset unless explicitly documented aliases resolve them.

## Location records

Planned files:

- `locations/india-states.json`
- `locations/india-districts.json`

State records extend the common record with:

```json
{
  "code": "IN_GJ",
  "label": "Gujarat",
  "type": "state",
  "active": true,
  "sortOrder": 10,
  "aliases": []
}
```

Union Territories use `type: "union_territory"`.

District records extend the common record with a required parent:

```json
{
  "code": "IN_GJ_AHMEDABAD",
  "stateCode": "IN_GJ",
  "label": "Ahmedabad",
  "active": true,
  "sortOrder": 10,
  "aliases": []
}
```

Every `stateCode` must exist in the State dataset. Codes must remain stable when display spelling changes. Dataset provenance, retrieval date, jurisdiction coverage, licence/usage terms, and source version must be recorded beside the imported data before approval.

## Planned controlled datasets

- `education.json`
- `iti-trades.json`
- `diploma-branches.json`
- `engineering-branches.json`
- `degree-courses.json`
- `industries.json`
- `job-roles.json`
- `experience-levels.json`
- `employment-types.json`
- `shift-types.json`
- `availability-options.json`
- `gender-options.json`

Dependency-bearing records add explicit parent codes; for example a course record uses `educationCodes`, and a job role may use `industryCodes`. UI code must derive dependent options from these relationships rather than duplicating arrays in forms.

## Compatibility contract

Existing database fields contain historical free text. Reference-data adoption must not rewrite those values. Migrated forms should submit stable codes only where the existing database contract safely supports them; otherwise they should resolve the selected code to the current label at the compatibility boundary. Displays must fall back to historical text when no canonical code is present.

No production form imports this directory in R3.
