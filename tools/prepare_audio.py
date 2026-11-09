"""Prepare the selected CC0 audio assets. See assets/audio/CREDITS.txt for sources.
Input: .runtime/audio-source/{interface,casino,impact,rpg}.zip, menu.ogg, battle.flac.
No runtime dependency: exports contain only the resulting Ogg Vorbis files.
"""
from pathlib import Path
import io, zipfile, hashlib
import numpy as np
import soundfile as sf

source=Path('.runtime/audio-source'); target=Path('assets/audio'); target.mkdir(parents=True,exist_ok=True)
selections={
 'click':('interface','click_003'), 'open':('rpg','bookOpen'), 'close':('rpg','bookClose'),
 'card':('casino','card-slide-4'), 'draw':('casino','card-shove-1'),
 'deploy':('casino','card-place-2'), 'move':('casino','card-slide-8'),
 'attack':('rpg','cloth2'), 'damage':('impact','impactPunch_heavy_000'),
 'death':('impact','impactPlank_medium_000'), 'counter':('impact','impactMetal_light_002'),
 'order':('interface','confirmation_002'), 'heal':('interface','glass_001'),
 'turn':('interface','bong_001'), 'victory':('interface','confirmation_004'),
 'defeat':('interface','back_004'),
}
for name,(pack,original) in selections.items():
 with zipfile.ZipFile(source/(pack+'.zip')) as z:
  data,rate=sf.read(io.BytesIO(z.read('Audio/'+original+'.ogg')),always_2d=True)
  # Consistent peak headroom, no amplification of near-silent assets.
  data *= min(1.5, 0.60/max(0.01,float(np.max(np.abs(data)))))
  sf.write(target/(name+'.ogg'),data,rate,format='OGG',subtype='VORBIS')
for name,filename in []:  # Music replaced in 0.8.46; use prepare_touhou_audio.py.
 data,rate=sf.read(source/filename,always_2d=True)
 data *= min(1.0,0.72/max(0.01,float(np.max(np.abs(data)))))
 with sf.SoundFile(target/(name+'.ogg'),'w',samplerate=rate,channels=data.shape[1],format='OGG',subtype='VORBIS') as output:
  for offset in range(0,len(data),16384): output.write(data[offset:offset+16384])
 print(name,'seconds',round(len(data)/rate,2),'bytes',(target/(name+'.ogg')).stat().st_size)
for pack in ['interface','casino','impact','rpg']:
 with zipfile.ZipFile(source/(pack+'.zip')) as z:
  (target/(pack+'-license.txt')).write_bytes(z.read('License.txt'))
for path in sorted(target.glob('*.ogg')):
 info=sf.info(path)
 print(path.name,round(info.duration,2),hashlib.sha256(path.read_bytes()).hexdigest())

