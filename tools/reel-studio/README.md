# Aadhyant Hindi Reel Studio

Working local renderer for a recruitment post: Hindi spoken narration, original quiet musical bed, 1080 × 1920 MP4 and WhatsApp contact on each card. Optional JPG/PNG cover. No Meta publishing and no candidate messaging.

## Start

Requires Python 3.11+, FFmpeg/ffprobe on PATH and internet access for voice synthesis.

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

Voice uses the same `edge-tts` route used for the manually produced Reel. It is an unofficial client, requires no account key, and availability is best-effort. Failures are shown and retries are bounded; replace `synthesize()` with a contracted TTS provider if service guarantees are required. Only public recruitment facts and the intended public contact are sent for voice generation. No candidate information, credentials or internal notes are included. TLS verification remains enabled.

The local HTTP studio remains local-only: do not expose it publicly or remove its localhost restriction. Online operation uses the separately authenticated Edge/runner path, not this HTTP server.

Hindi font: Noto Sans Devanagari, SIL Open Font License (bundled). `REEL_FONT` can supply another shaping-compatible font. Music is generated mathematically without an external recording.

## Verification

```sh
python -m unittest discover -s tools/reel-studio -p 'test_*.py'
```

The HTTP endpoint uses a random per-process same-origin request token, validates Host to prevent DNS rebinding, limits body/poster size and permits only one generation at once. Downloads accept only known random job IDs. The local HTTP endpoint does not perform database writes or publish content. The online integration has separate scoped RPCs; neither path sends WhatsApp messages or publishes Meta advertisements.
