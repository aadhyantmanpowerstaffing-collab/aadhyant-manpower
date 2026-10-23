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

## Current boundaries / portal integration

This is **local-only**, not a deployed portal feature or an automatic post-save hook. The portal is static GitHub Pages and cannot execute FFmpeg. Live automatic rendering requires a durable background worker, authenticated job submission, private result storage, job status/retries and an explicit render trigger from the canonical employer requirement save workflow. These are not supplied or deployed by this change. Do not make this local HTTP server publicly accessible or remove its localhost restriction.

Voice uses the unofficial `edge-tts` client (the same voice route used for the manually produced reel). It requires no configured account key but its service availability is not guaranteed. A supported, licensed TTS provider and its credentials must be selected/configured before this becomes an unattended production service. Input text is sent to that voice service; do not include private candidate information. No credentials are bundled. TLS verification remains enabled.

Hindi font: Noto Sans Devanagari, SIL Open Font License (bundled). `REEL_FONT` can supply another shaping-compatible font. Music is generated mathematically without an external recording.

## Verification

```sh
python -m unittest discover -s tools/reel-studio -p 'test_*.py'
```

The HTTP endpoint uses a random per-process same-origin request token, validates Host to prevent DNS rebinding, limits body/poster size and permits only one generation at once. Downloads accept only known random job IDs. No database changes, external publishing, WhatsApp sends, or existing website changes.
