# W0 Git Baseline

Baseline captured 2026-08-19 from repository files and locally cached Git references. No fetch, checkout, branch creation, stash, reset, clean, commit, push, or worktree mutation was performed.

## Repository state

- Current worktree: `D:\Projects\Aadhyant site`
- Current branch: `v2-development`
- HEAD: `98db2ad`
- Upstream: `origin/v2-development`
- Locally calculated divergence: 8 commits ahead, 0 behind. This is relative to the cached remote-tracking reference; the remote server was not contacted.
- Staged changes: none
- Modified tracked files: 2
- Untracked items before creation of the three W0 reports: 9

Local branches:

| Branch | Commit | Upstream | Worktree |
|---|---:|---|---|
| `v2-development` | `98db2ad` | `origin/v2-development` | `D:\Projects\Aadhyant site` |
| `main` | `29e0e55` | `origin/main` | `D:\Projects\Aadhyant-main-deploy` |

Locally known remote branches are `origin/main` and `origin/v2-development`; `origin/HEAD` points to `origin/main`. `main...v2-development` is 1/1 divergent with merge base `ddc7d09`. Do not rebase, reset, or assume either branch can overwrite the other.

The eight commits reported ahead of cached `origin/v2-development` are:

1. `98db2ad` Merge `main` into `v2-development`
2. `822a62f` Add Meta WhatsApp legal pages
3. `7e66ec8` Merge branch `v2-development`
4. `d3215d5` Merge branch `v2-development`
5. `9c0eb84` Merge branch `v2-development`
6. `5f92b6d` Merge branch `v2-development`
7. `f94f856` Merge branch `v2-development`
8. `ea2ca0e` Merge branch `v2-development`

## Uncommitted-work inventory

| Path | Git state | Classification | Assessment |
|---|---|---|---|
| `company/company.js` | modified | existing product work | Portal reads/mutations changed from direct table/older RPC access to migration 015 projection/wrapper RPCs. Preserve with 015. |
| `contractor/contractor.js` | modified | existing product work | Partner assignment reads/responses changed to migration 015 projection/wrapper RPCs. Preserve with 015. |
| `supabase/migrations/015_tenant_requirement_security_boundary.sql` | untracked | Supabase migration | Additive security-boundary migration; not proof of production application. |
| `supabase/tests/015_tenant_requirement_security_boundary_test.sql` | untracked | test | Companion SQL regression test for migration 015. |
| `PRE_R14_PREFLIGHT.sql` | untracked | Supabase migration support / test | Read-only preflight/diagnostic SQL for the R14 security work. |
| `RECONSTRUCTION_PRE_R14_C1_TENANT_SECURITY.md` | untracked | documentation | Security reconstruction notes for the same work bundle. |
| `favicon.ico` | untracked | existing product asset; provenance unknown | Not an obvious temporary artifact. Confirm intended source/ownership before committing. |
| `WEB_PLATFORM_ARCHITECTURE.md` | untracked | documentation | Prior architecture-blueprint deliverable. |
| `WEB_PLATFORM_SCHEMA.md` | untracked | documentation | Prior schema-blueprint deliverable. |
| `DESKTOP_TO_WEB_MIGRATION.md` | untracked | documentation | Prior migration-mapping deliverable. |
| `WEB_PLATFORM_MILESTONES.md` | untracked | documentation | Prior roadmap deliverable. |

No clearly disposable generated/temp artifact was identified. The W0 reports themselves become additional untracked documentation after this captured baseline.

## Safe branch and worktree strategy

Do **not** create or switch to `web-platform-development` in the current dirty worktree. A branch switch would mix or strand the security bundle, while a new worktree created from current HEAD would omit every uncommitted file.

Recommended sequence:

1. Owner-review the migration 015 bundle (`015` SQL, test, preflight, reconstruction notes, and both portal JS changes) as one coherent security change. Confirm whether `favicon.ico` belongs to that work or a separate product commit.
2. Test the bundle against a non-production Supabase environment or disposable database. Do not infer production state from SQL files.
3. Commit coherent changes on `v2-development` in separate commits: security implementation/test; product asset if approved; architecture/W0 documentation.
4. Fetch and compare the real remote only after authorization, reconcile without rewriting history, then push `v2-development` and verify it is clean.
5. Create an isolated worktree from that reviewed commit, rather than switching this worktree:

   `git worktree add -b web-platform-development "D:\Projects\Aadhyant-web-platform" v2-development`

6. Set/push the upstream only when W1 development is authorized.

Do not stash by default: a stash is easier to forget and does not establish an auditable baseline. Do not branch from `main` until its one unique commit and the one unique `v2-development` history segment are deliberately reconciled.

## Exact next action before W1

Review and validate the existing migration 015 security bundle in a non-production environment, decide the provenance of `favicon.ico`, then commit the preserved work on `v2-development`. Only after a clean, fetched, reconciled, pushed baseline should the separate `web-platform-development` worktree be created.
