"""Local-only recruitment reel studio. No publishing or candidate messaging."""
import asyncio
import base64
import io
import json
import math
import os
from pathlib import Path
import re
import secrets
import shutil
import ssl
import subprocess
import tempfile
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
OUT = Path(os.environ.get('REEL_OUTPUT_DIR', str(Path.home() / 'Aadhyant-Reels'))).resolve()
FONT = Path(os.environ.get('REEL_FONT', str(ROOT / 'NotoSansDevanagari.ttf')))
TOKEN = secrets.token_urlsafe(32)
JOBS = {}
BUSY = threading.Semaphore(1)


def validate(data):
    if not isinstance(data, dict):
        raise ValueError('Enter the post details.')
    text = str(data.get('text', '')).strip()
    if not 10 <= len(text) <= 1800:
        raise ValueError('Post text must contain 10–1800 characters.')
    contact = re.sub(r'\D', '', str(data.get('phone', '9586785800')))
    if not re.fullmatch(r'[6-9]\d{9}', contact):
        raise ValueError('Enter a valid 10-digit contact number.')
    name = str(data.get('name', 'Hitesh Gadhavi')).strip()
    if not 1 <= len(name) <= 50:
        raise ValueError('Contact name must contain 1–50 characters.')
    title = str(data.get('title', 'नौकरी का अवसर')).strip()
    if not 1 <= len(title) <= 80:
        raise ValueError('Title must contain 1–80 characters.')
    return {'text': text, 'phone': contact, 'name': name, 'title': title, 'poster': data.get('poster')}


def lines_for(draw, text, font, width):
    lines = []
    for paragraph in text.splitlines():
        line = ''
        for word in paragraph.split():
            candidate = (line + ' ' + word).strip()
            if draw.textlength(candidate, font=font) > width:
                if line:
                    lines.append(line)
                line = word
                # Break long tokens as well; do not silently clip them.
                while draw.textlength(line, font=font) > width:
                    end = 1
                    while end < len(line) and draw.textlength(line[:end + 1], font=font) <= width:
                        end += 1
                    lines.append(line[:end])
                    line = line[end:]
            else:
                line = candidate
        if line:
            lines.append(line)
    return lines


def centered(draw, text, y, size, color='#FFFFFF', width=920):
    while size >= 20:
        f = ImageFont.truetype(str(FONT), size)
        if draw.textlength(text, font=f) <= width:
            break
        size -= 2
    box = draw.textbbox((0, 0), text, font=f)
    draw.text(((1080 - draw.textlength(text, font=f)) / 2, y - box[1]), text, font=f, fill=color)


def cards(data, work):
    dummy = ImageDraw.Draw(Image.new('RGB', (1080, 1920)))
    bodyfont = ImageFont.truetype(str(FONT), 54)
    lines = lines_for(dummy, data['text'], bodyfont, 880)
    pages = [lines[i:i + 8] for i in range(0, len(lines), 8)]
    poster = None
    if data.get('poster'):
        try:
            raw = base64.b64decode(data['poster'], validate=True)
            if len(raw) > 6_000_000:
                raise ValueError()
            with Image.open(io.BytesIO(raw)) as src:
                if src.width * src.height > 20_000_000:
                    raise ValueError()
                src.load()
                poster = src.convert('RGB')
        except Exception:
            raise ValueError('Choose a valid JPG or PNG poster smaller than 6 MB.') from None
    if poster is not None:
        pages = [[]]
    paths = []
    for index, page in enumerate(pages):
        im = Image.new('RGB', (1080, 1920), '#071923')
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((60, 180, 1020, 330), radius=25, fill='#BAD432')
        centered(d, 'AADHYANT', 210, 64, '#071923')
        centered(d, 'MANPOWER & STAFFING', 290, 28, '#071923')
        centered(d, data['title'], 395, 64, '#BAD432')
        if poster is not None:
            # Alternate poster card and text cards so every fact remains readable.
            if index == 0:
                poster.thumbnail((880, 580))
                im.paste(poster, ((1080 - poster.width) // 2, 520))
        top = 560 if poster is None or index != 0 else 1140
        if poster is not None and index == 0:
            # Full text follows in separate cards; poster is a cover only.
            page = ['भर्ती का पूरा विवरण आगे देखें']
        for j, line in enumerate(page):
            centered(d, line, top + j * 88, 54)
        d.rectangle((100, 1440, 980, 1444), fill='#BAD432')
        centered(d, data['name'], 1500, 46)
        centered(d, data['phone'], 1590, 88, '#BAD432')
        centered(d, 'WhatsApp पर नाम और इलाका भेजें', 1720, 43)
        path = work / f'card-{len(paths)}.png'
        im.save(path)
        paths.append(path)
    if poster is not None:
        # Re-render all text without the cover, then preserve its ordering.
        paths += cards({**data, 'poster': None}, work / 'body')
    return paths


async def synthesize(text, target):
    import edge_tts
    import edge_tts.communicate
    # Use system trust, including installed corporate CA roots. Never disable TLS.
    cafile = os.environ.get('SSL_CERT_FILE', '/etc/ssl/certs/ca-certificates.crt')
    if Path(cafile).is_file():
        edge_tts.communicate._SSL_CTX = ssl.create_default_context(cafile=cafile)
    await edge_tts.Communicate(text, 'hi-IN-MadhurNeural', rate='+5%').save(str(target))


def render(data, target):
    data = validate(data)
    if not FONT.is_file():
        raise RuntimeError('Hindi font is missing. Run setup first.')
    if not shutil.which('ffmpeg') or not shutil.which('ffprobe'):
        raise RuntimeError('FFmpeg and ffprobe must be installed.')
    with tempfile.TemporaryDirectory(prefix='aadhyant-reel-') as tmp:
        work = Path(tmp)
        (work / 'body').mkdir()
        images = cards(data, work)
        spoken_digits = ' '.join({'0':'शून्य','1':'एक','2':'दो','3':'तीन','4':'चार','5':'पाँच','6':'छह','7':'सात','8':'आठ','9':'नौ'}[x] for x in data['phone'])
        script = f"{data['title']}। {data['text']}। संपर्क करें {data['name']}। व्हाट्सऐप नंबर है {spoken_digits}। अपना नाम और इलाका भेजें।"
        voice = work / 'voice.mp3'
        asyncio.run(synthesize(script, voice))
        duration = float(subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=nw=1:nk=1', str(voice)])) + 1
        if duration > 180:
            raise ValueError('This narration exceeds 3 minutes. Shorten the post.')
        # Original generated musical bed; narration is mixed at full level.
        with wave.open(str(work / 'music.wav'), 'wb') as wav:
            wav.setparams((1, 2, 24000, 0, 'NONE', 'not compressed'))
            import array
            samples = array.array('h')
            notes = (261.63, 329.63, 392.0, 329.63)
            for n in range(24000 * 4):
                t = n / 24000
                frequency = notes[int(t) % 4]
                envelope = min(1, (t % 1) * 12) * max(0, 1 - t % 1)
                samples.append(int(600 * envelope * math.sin(2 * math.pi * frequency * t)))
            if os.sys.byteorder != 'little':
                samples.byteswap()
            wav.writeframes(samples.tobytes())
        # Use a concat image sequence: fixed resource use regardless of card count.
        frames = work / 'frames.txt'
        entries = []
        weights = [max(1, len(data['text']) / len(images)) for _ in images]
        for img, weight in zip(images, weights):
            entries += [f"file '{img.as_posix()}'", f'duration {duration * weight / sum(weights):.6f}']
        entries += [f"file '{images[-1].as_posix()}'"]
        frames.write_text('\n'.join(entries), encoding='utf-8')
        subprocess.run(['ffmpeg','-y','-v','error','-threads','2','-filter_complex_threads','1',
            '-f','concat','-safe','0','-i',str(frames),'-i',str(voice),'-stream_loop','-1','-i',str(work / 'music.wav'),
            '-filter_complex','[0:v]fps=25,format=yuv420p[v];[1:a]apad[a1];[2:a]volume=0.5[a2];[a1][a2]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[a]',
            '-map','[v]','-map','[a]','-t',str(duration),'-c:v','libx264','-threads','2','-preset','fast','-crf','23','-c:a','aac','-b:a','128k','-movflags','+faststart',str(target)], check=True, timeout=360)
        target.with_suffix('.json').write_text(json.dumps({**data,'poster':None,'narration':script,'duration':round(duration,2)}, ensure_ascii=False, indent=2), encoding='utf-8')


def run_job(identifier, data):
    try:
        OUT.mkdir(parents=True, exist_ok=True)
        render(data, OUT / f'{identifier}.mp4')
        JOBS[identifier] = {'status':'ready', 'url':f'/video/{identifier}.mp4'}
    except Exception as exc:
        # Do not leak paths, remote headers or input text in API errors.
        JOBS[identifier] = {'status':'failed', 'error':str(exc) if isinstance(exc, ValueError) else 'Video generation failed. Check the renderer, voice connection and font installation; then retry.'}
    finally:
        BUSY.release()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def respond(self, status, data, mime='application/json'):
        raw = json.dumps(data).encode() if mime == 'application/json' else data
        self.send_response(status)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.end_headers()
        self.wfile.write(raw)

    def trusted_host(self):
        return self.headers.get('Host') in {f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}'}

    def do_GET(self):
        if not self.trusted_host():
            return self.respond(403, {'error':'Local access only.'})
        path = urlparse(self.path).path
        if path == '/':
            return self.respond(200, (ROOT/'studio.template').read_text().replace('__TOKEN__', TOKEN).encode(), 'text/html; charset=utf-8')
        if path.startswith('/job/'):
            identifier = path.rsplit('/',1)[-1]
            return self.respond(200 if identifier in JOBS else 404, JOBS.get(identifier, {'error':'Job not found.'}))
        match = re.fullmatch(r'/video/([a-f0-9]{32})\.mp4', path)
        if match and JOBS.get(match[1], {}).get('status') == 'ready':
            return self.respond(200, (OUT/f'{match[1]}.mp4').read_bytes(), 'video/mp4')
        return self.respond(404, {'error':'Not found.'})

    def do_POST(self):
        if not self.trusted_host() or self.headers.get('X-Reel-Token') != TOKEN:
            return self.respond(403, {'error':'Open the local studio and retry.'})
        if self.path != '/generate':
            return self.respond(404, {'error':'Not found.'})
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 < length <= 8_500_000:
                return self.respond(413, {'error':'Post or image is too large.'})
            data = validate(json.loads(self.rfile.read(length)))
        except (ValueError, TypeError):
            return self.respond(400, {'error':'Check the post, title and 10-digit contact number.'})
        if not BUSY.acquire(blocking=False):
            return self.respond(429, {'error':'One video is being generated. Please wait.'})
        identifier = secrets.token_hex(16)
        JOBS[identifier] = {'status':'rendering'}
        threading.Thread(target=run_job, args=(identifier,data), daemon=True).start()
        return self.respond(202, {'id':identifier})


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--json', type=Path, help='Generate once from a JSON request instead of opening the studio')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.json:
        if not args.output:
            parser.error('--output is required with --json')
        render(json.loads(args.json.read_text(encoding='utf-8')), args.output)
        print(f'Video saved: {args.output}')
    else:
        print(f'Aadhyant Reel Studio: http://127.0.0.1:{args.port}', flush=True)
        ThreadingHTTPServer(('127.0.0.1', args.port), Handler).serve_forever()
