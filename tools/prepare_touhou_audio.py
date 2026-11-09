"""Convert official TAGeLorix downloads. See assets/audio/CREDITS.txt.
Place Kawaii Koumakan.mp3 and Remiliaize.mp3 under .runtime/audio846 as
menu.mp3 and battle.mp3. Sound effects remain unchanged.
"""
from pathlib import Path
import hashlib
import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {
    "menu": "8ffe29b420140791b62a4603c4a32a42d4ae48cc3a719bf15cc831abca890a09",
    "battle": "1f386f6216937dca443a5f3ec4bf82e0e9a80de7f9c61b9570cdbc329da8cd45",
}
for name, expected in SOURCES.items():
    source = ROOT / ".runtime/audio846" / (name + ".mp3")
    assert hashlib.sha256(source.read_bytes()).hexdigest() == expected
    samples, rate = sf.read(source, always_2d=True)
    samples *= min(.70 / float(np.max(np.abs(samples))),
                   .14 / float(np.sqrt(np.mean(samples * samples))))
    fade = int(rate * .025)
    samples[:fade] *= np.linspace(0, 1, fade)[:, None]
    samples[-fade:] *= np.linspace(1, 0, fade)[:, None]
    target = ROOT / "assets/audio" / (name + ".ogg")
    with sf.SoundFile(target, "w", samplerate=rate, channels=2,
                      format="OGG", subtype="VORBIS") as output:
        for offset in range(0, len(samples), 16384):
            output.write(samples[offset:offset + 16384])
    print(name, round(len(samples) / rate, 2), hashlib.sha256(target.read_bytes()).hexdigest())
