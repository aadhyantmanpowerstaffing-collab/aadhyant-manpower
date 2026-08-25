# Isolated staging deployment plan

This repository currently has no configured staging account or deployment. The planned target is the separate Cloudflare Pages project `aadhyant-web-platform-staging` at `https://aadhyant-web-platform-staging.pages.dev`, using GitHub Environment `staging` and only NONPROD project `zrluniaccvcdrvfwgrmj`.

The staging builder writes only `dist-staging/`; the production builder, production config, and production Pages workflow remain separate and unchanged. Required future Environment secret: `STAGING_SUPABASE_PUBLISHABLE_KEY`. The deployment token, when separately approved, must be scoped only to this Pages project. No service-role key, database password, or production secret is permitted.

Account creation, token/secret setup, and deployment remain disabled until separately authorized. Rollback is selecting the prior known-good Cloudflare Pages deployment or redeploying its recorded artifact digest.
