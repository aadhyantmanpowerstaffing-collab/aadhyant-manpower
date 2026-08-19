# Staging Guard Skeleton

`verify-staging-target.ps1` is a non-destructive static preflight. It validates the Git branch/commit, required private configuration, exact staging URL/project identity, direct or session-pooler database identity, production denylists, and an aggregate checksum over `schema.sql` plus migrations 007–016.

It does not connect to Supabase, execute SQL, reset data, apply migrations, create users, or authorize a mutation by itself. A future separately reviewed wrapper must perform a positive read-only database identity query immediately before each mutation and must abort if either this static guard or the remote identity check fails.

Run only after filling the ignored `.env.staging.local` privately:

```powershell
& .\scripts\staging\verify-staging-target.ps1
```

The script prints no configured credentials. Do not add secret values to command-line arguments or shell history.
