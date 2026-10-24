# Aadhyant Hindi Reel Studio

Working local renderer for a recruitment post: Hindi spoken narration, original quiet musical bed, 1080 × 1920 MP4 and WhatsApp contact on each card. Optional JPG/PNG cover. No Meta publishing and no candidate messaging.

## Start

Requires Python 3.11+ and FFmpeg/ffprobe on PATH. Install `espeak-ng` for offline Hindi speech (`sudo apt-get install espeak-ng` on Ubuntu). The default voice mode tries the existing online voice for up to 45 seconds and uses offline speech if unavailable. No OpenAI account or paid voice API is needed.

```sh
python -m pip install -r tools/reel-studio/requirements.txt
python tools/reel-studio/studio.py
```

Open http://127.0.0.1:8765 . Paste finalized Hindi post text, set heading and contact, and select **Create Hindi Reel**. The studio generates the voice, cards and MP4, then shows a playable preview and download. Text is spoken as entered; this does not translate Gujarati or English and does not OCR poster text. Include the poster's complete facts in the narration box. Default contact: Hitesh Gadhavi, 9586785800.

Videos and their narration manifests are retained in `~/Aadhyant-Reels`. Set `REEL_OUTPUT_DIR` to change the folder. Stop with Ctrl+C. There is no automatic deletion of completed work.

Batch/API integration entry point:

```sh
python tools/reel-studio/studio.py --json tools/reel-studio/example.json --output reel.mp4
```

The renderer synthesizes exactly the approved text and appends the name/contact. Hindi phone digits are expanded individually. A post can be up to 1800 characters; audio longer than three minutes is rejected. Generated text card timings are evenly distributed and are not word-synchronized subtitles. Review salaries, facts and pronunciation before publishing.

## Portal integration

`admin/reels.html` lists private generated videos and can queue an existing approved, public, open canonical requirement. The additive Reel migration installs a derived media queue, a guarded publication trigger and Admin/worker RPCs. Installation starts paused and does not backfill old vacancies or send messages.

`.github/workflows/recruitment-reels.yml` on the default `main` branch checks out an immutable reviewed renderer revision. A GitHub-hosted runner polls every five minutes (GitHub may delay scheduled runs), claims at most one job and uses `cloud_worker.py` to create and return the MP4. The Edge endpoint validates GitHub's RS256 signature, audience, repository/owner IDs, main branch, exact workflow path, approved workflow SHA, event, hosted runner and token lifetime. No service-role key is stored in GitHub. A rotated per-job claim binds uploads and completions to one run, with a 15-minute lease and three attempts. The queue has a default rolling cap of 30 jobs per day.

The private Storage bucket is never public. The browser obtains a five-minute signed preview only after the existing server-side Admin check and current vacancy fingerprint/eligibility check. Closing or changing a job invalidates the previous preview request. Source figures and terms are read from the existing canonical public job summary, not independently inferred from a poster. The final voice reads Hindi framing with the job's stored names and values; it does not translate every English free-text value. Admin must review pronunciation and facts before sharing.

The preferred online voice uses the same `edge-tts` route used for the manually produced Reel. It is an unofficial client, requires no account key, and availability is best-effort. Failures are shown and retries are bounded; replace `synthesize()` with a contracted TTS provider if service guarantees are required. Only public recruitment facts and the intended public contact are sent for voice generation. No candidate information, credentials or internal notes are included. TLS verification remains enabled.

The local HTTP studio remains local-only: do not expose it publicly or remove its localhost restriction. Online operation uses the separately authenticated Edge/runner path, not this HTTP server.

Hindi font: Noto Sans Devanagari, SIL Open Font License (bundled). `REEL_FONT` can supply another shaping-compatible font. Music is generated mathematically without an external recording.

## Verification

```sh
python -m unittest discover -s tools/reel-studio -p 'test_*.py'
```

The HTTP endpoint uses a random per-process same-origin request token, validates Host to prevent DNS rebinding, limits body/poster size and permits only one generation at once. Downloads accept only known random job IDs. The local HTTP endpoint does not perform database writes or publish content. The online integration has separate scoped RPCs; neither path sends WhatsApp messages or publishes Meta advertisements.

## Free offline voice

Set `REEL_VOICE_PROVIDER=offline` to keep narration entirely local. `auto` (default) prefers the existing online voice and falls back to eSpeak NG; `edge` explicitly requires the online voice. eSpeak NG Hindi is a basic synthetic voice, less natural than the online voice. The output JSON records `voice_provider` so operators can identify fallback videos. Network failures do not trigger any paid provider.

```sh
REEL_VOICE_PROVIDER=offline python tools/reel-studio/studio.py --json tools/reel-studio/example.json --output reel.mp4
```

The free voice software has no per-video API fee. Hosted runner minutes and storage are separate resources and may incur charges outside their free allowances; this change does not enable billing. This is still the existing portal job-details-to-video flow. Arbitrary poster OCR/translation is not implemented by this change.

Deployment must install `espeak-ng` on the runner and update the immutable renderer revision. Retain the existing OIDC verification and approved workflow SHA gate; do not bypass either. Local tests alone do not activate the new voice on the live portal.

## Poster upload in the portal

Admin → Hindi Reel Studio now includes a poster workflow. JPG/PNG recruitment posters up to 6 MB are read locally with pinned Tesseract.js 6.0.1 (English, Hindi + English, Gujarati + English). Language/engine downloads come from the configured public CDN; the poster itself is not uploaded for OCR. Chrome's built-in Translator API can translate English to Hindi on supported desktop devices, with no paid API key. Gujarati automatic translation and mobile/unsupported-browser translation are not provided: the source remains editable and the operator enters the final Hindi narration. Names, amounts and OCR can be wrong; no translation is automatically approved. Numeric changes detected during translation reject that draft.

Before queueing, the Admin must review and confirm the complete final Hindi text. The poster is compressed as JPEG locally, then uploaded only as part of that reviewed media request. Queueing reuses `private.requirement_reels`, its current worker, bounded retries and private MP4 storage. It does not create a fake vacancy, update a canonical requirement, publish an ad or send WhatsApp. Idempotent request IDs prevent duplicate submissions; changing text invalidates the prior client review. Only Admin RPCs can queue/list/preview these media. Poster payloads are snapshotted and fingerprinted; job videos still require current canonical eligibility. The same daily submission cap bounds poster uploads.

The upgrade migration is additive. Deploy it before the frontend; the renderer already supports poster covers. Production activation requires the repository's explicit deployment approval.


## Poster OCR quality correction (24 October 2026)

The portal now defaults to mixed Hindi + English. OCR uses a separate, uncompressed image up to 3200 pixels on its longest edge; the smaller JPEG remains only the video cover. Sparse-text passes read original colour and fixed high-contrast images, supplemented by separate column reads. Low-confidence decorative lines are excluded. Up to 24 uncertain numeric regions are reread as isolated English text lines, prioritizing long numbers. Conflicting numbers that remain unresolved are excluded from the automatic narration and listed for the Admin to correct or add before creating the video. This is local Tesseract OCR, not semantic vision: company names, spelling, layout and omitted details still require visual review.

Hindi is no longer populated directly from raw mixed-language OCR. The draft translates clean English-containing lines and retains Hindi-only lines. Changing the source or language clears stale narration. Existing translation number checks, final explicit review, private media queue and Admin access remain intact. No new API key, database migration, messaging or renderer revision is required.

Validation used the operator's selected FCC poster with the real pinned Tesseract.js worker, not only mocked output. It recovered the configured phone, salary ranges, overtime rates, duty and interview dates; some names and decorative header text still require review. Automated tests cover the reported garbage, mixed script, conflicting amounts, lost duty/time digits, stale narration and existing queue protections. This does not guarantee perfect OCR for every poster or verify Chrome's on-device translation quality.


## Hindi draft blocker correction

A global reliability check could reject an entire readable poster and leave step 3 blank with “unreadable marks.” Draft preparation now filters individual unreadable fragments and unresolved numeric lines while keeping the remaining recruitment text. The original source stays editable. Excluded lines are listed visibly beside the draft button, and the existing final review explicitly includes omitted details. Low confidence is advisory when substantial readable text exists; entirely unreadable input still fails clearly. Salary/phone changes during translation still reject the draft. The progress/error message now appears immediately below Create Hindi draft rather than below the video submission button.

This fixes the blanket quality rejection; it does not supply an alternative translation engine. Mixed-language translation still requires the supported Chrome Translator API. Unsupported-browser and translation errors remain explicit and keep the Hindi field editable.
