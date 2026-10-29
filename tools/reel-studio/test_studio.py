import base64
import importlib.util
import io
import tempfile
import unittest
import asyncio
from unittest.mock import AsyncMock, patch
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
spec = importlib.util.spec_from_file_location('studio', Path(__file__).with_name('studio.py'))
studio = importlib.util.module_from_spec(spec)
spec.loader.exec_module(studio)

class StudioTests(unittest.TestCase):
    def test_offline_mode_never_calls_online_service(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(studio.os.environ, {'REEL_VOICE_PROVIDER':'offline'}), patch.object(studio, 'synthesize_online', new_callable=AsyncMock) as online, patch.object(studio.shutil, 'which', return_value='/usr/bin/espeak-ng'), patch.object(studio.subprocess, 'run') as run:
            self.assertEqual(asyncio.run(studio.synthesize('भर्ती का अवसर', Path(tmp)/'voice.mp3')), 'espeak-ng')
            online.assert_not_called()
            self.assertEqual(run.call_args_list[0].kwargs['input'], 'भर्ती का अवसर')
    def test_online_failure_uses_offline_and_removes_partial_audio(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(studio.os.environ, {'REEL_VOICE_PROVIDER':'auto'}), patch.object(studio, 'synthesize_online', new_callable=AsyncMock, side_effect=TimeoutError), patch.object(studio.shutil, 'which', return_value='/usr/bin/espeak-ng'), patch.object(studio.subprocess, 'run'):
            target=Path(tmp)/'voice.mp3'; target.write_bytes(b'partial')
            self.assertEqual(asyncio.run(studio.synthesize('भर्ती का अवसर', target)), 'espeak-ng')
            self.assertFalse(target.exists())
    def test_missing_offline_dependency_gives_safe_actionable_error(self):
        with patch.dict(studio.os.environ, {'REEL_VOICE_PROVIDER':'offline'}), patch.object(studio.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(RuntimeError, 'Install espeak-ng'):
                asyncio.run(studio.synthesize('भर्ती का अवसर', Path('voice.mp3')))
    def test_online_only_failure_does_not_silently_change_voice(self):
        with patch.dict(studio.os.environ, {'REEL_VOICE_PROVIDER':'edge'}), patch.object(studio, 'synthesize_online', new_callable=AsyncMock, side_effect=TimeoutError), patch.object(studio.subprocess, 'run') as run:
            with tempfile.TemporaryDirectory() as tmp, self.assertRaisesRegex(RuntimeError, 'Online voice is unavailable'):
                asyncio.run(studio.synthesize('भर्ती का अवसर', Path(tmp)/'voice.mp3'))
            run.assert_not_called()
    def data(self):
        return dict(text='साणंद में सुरक्षा गार्ड की भर्ती। योग्यता दसवीं पास।', phone='8128254272', name='Hitesh Gadhavi', title='भर्ती')
    def test_reject_invalid_and_short_data(self):
        for item in [None, {}, {**self.data(),'phone':'123'}, {**self.data(),'text':'x'*1801}]:
            with self.assertRaises(ValueError): studio.validate(item)
    def test_cards_preserve_long_text(self):
        data=self.data(); data['text']='\n'.join('सुरक्षा गार्ड की भर्ती '+str(i) for i in range(30))
        with tempfile.TemporaryDirectory() as tmp:
            paths=studio.cards(studio.validate(data),Path(tmp))
            self.assertGreater(len(paths),1)
            for path in paths:
                with Image.open(path) as im: self.assertEqual(im.size,(1080,1920))
    def test_poster_does_not_drop_or_duplicate_text_cards(self):
        buf=io.BytesIO(); Image.new('RGB',(200,300),'red').save(buf,format='PNG')
        data={**self.data(),'poster':base64.b64encode(buf.getvalue()).decode()}
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp)/'body').mkdir()
            self.assertEqual(len(studio.cards(data,Path(tmp))),2)
    def test_corrupt_poster_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError): studio.cards({**self.data(),'poster':'invalid'},Path(tmp))
    def test_long_token_wraps_inside_card(self):
        draw=ImageDraw.Draw(Image.new('RGB',(1080,1920)))
        font=ImageFont.truetype(str(studio.FONT),54)
        lines=studio.lines_for(draw,'W'*200,font,880)
        self.assertEqual(''.join(lines),'W'*200)
        self.assertTrue(all(draw.textlength(x,font=font)<=880 for x in lines))

if __name__=='__main__': unittest.main()
