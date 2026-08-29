# Staging Guard

`verify-staging-target.ps1` is a non-destructive static preflight. It validates the Git branch/commit, required private configuration, exact staging URL/project identity, direct or session-pooler database identity, production denylists, and an aggregate checksum over `schema.sql` plus exactly migrations 007–036 (31 files total, with `schema.sql` first).

It does not connect to Supabase, execute SQL, reset data, apply migrations, create users, or authorize a mutation by itself. Migration 037 and later files are excluded from this approved manifest. A separately reviewed wrapper must perform a positive read-only database identity query immediately before any authorized remote operation and must abort if either this static guard or the remote identity check fails.

Run only after filling the ignored `.env.staging.local` privately:

```powershell
& .\scripts\staging\verify-staging-target.ps1
```

Run the local manifest/refusal assertions without reading private configuration or making a remote connection:

```powershell
& .\scripts\staging\verify-staging-target.ps1 -RunAssertionTests
& .\scripts\staging\verify-staging-identity.ps1 -RunAssertionTests
```

The scripts print no configured credentials. Do not add secret values to command-line arguments or shell history.
