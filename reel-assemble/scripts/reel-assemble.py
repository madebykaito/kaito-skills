#!/usr/bin/env python3
"""Assemble shots, voice, caption PNGs and a music bed into a vertical MP4."""
import argparse, json, os, pathlib, subprocess, sys

def run(cmd):
    p = subprocess.run(cmd, capture_output=True, text=True)
    if p.returncode: raise RuntimeError(p.stderr[-2000:])
    return p.stdout

def manifest_media(manifest_path, value):
    error = 'manifest media must be a relative regular file inside its directory'
    if not isinstance(value, str):
        raise ValueError(error)
    path = pathlib.Path(value)
    if path.anchor or '..' in path.parts:
        raise ValueError(error)
    root = manifest_path.parent
    path = (root / path).resolve()
    if root not in path.parents or not path.is_file():
        raise ValueError(error)
    return str(path)

def main():
    p = argparse.ArgumentParser(); p.add_argument('--shots', nargs='+', required=True); p.add_argument('--parts', required=True); p.add_argument('--captions', required=True); p.add_argument('--bed', required=True); p.add_argument('--out', required=True); p.add_argument('--fade', type=float, default=.5); a = p.parse_args()
    try:
        parts_path = pathlib.Path(a.parts).resolve(); parts = json.loads(parts_path.read_text()); duration = float(parts['duration'])
        voice = manifest_media(parts_path, parts['voice'])
        captions_path = pathlib.Path(a.captions).resolve(); captions = json.loads(captions_path.read_text()); entries = captions['captions']
        images = [manifest_media(captions_path, c['file']) for c in entries]
        if duration <= 0 or a.fade < 0: raise ValueError('duration must be positive and fade nonnegative')
        # Equal shot spans; extend each by the overlap so the finished timeline is voice length.
        span = duration / len(a.shots); fade = min(a.fade, span / 2)
        ff = os.environ.get('FFMPEG_BIN', 'ffmpeg'); cmd = [ff, '-v', 'error', '-y', '-filter_complex_threads', '1']
        for shot in a.shots:
            if pathlib.Path(shot).suffix.lower() in ('.png','.jpg','.jpeg','.webp'): cmd += ['-loop','1','-framerate','25']
            else: cmd += ['-stream_loop','-1']
            cmd += ['-i', shot]
        vi = len(a.shots); cmd += ['-i', voice, '-stream_loop','-1','-i',a.bed]
        for image in images: cmd += ['-loop','1','-i',image]
        filters = []
        for i in range(len(a.shots)):
            length = span + (fade if i < len(a.shots)-1 else 0)
            filters.append(f'[{i}:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1,fps=25,trim=duration={length},setpts=PTS-STARTPTS,format=yuv420p[v{i}]')
        cur = 'v0'
        for i in range(1,len(a.shots)):
            nxt=f'x{i}'
            if fade: filters.append(f'[{cur}][v{i}]xfade=transition=fade:duration={fade}:offset={i*span}[{nxt}]')
            else: filters.append(f'[{cur}][v{i}]concat=n=2:v=1:a=0[{nxt}]')
            cur=nxt
        for i,c in enumerate(entries):
            start=float(c['start']); end=float(c['end']); y=int(captions['y']); nxt=f'cap{i}'
            if end <= start: raise ValueError('caption end must follow start')
            filters.append(f"[{cur}][{vi+2+i}:v]overlay=0:{y}:enable='gte(t,{start})*lt(t,{end})'[{nxt}]"); cur=nxt
        filters += [f'[{vi}:a]aresample=48000,asplit=2[voice][side]', f'[{vi+1}:a]aresample=48000,volume=0.25[bed]', '[bed][side]sidechaincompress=threshold=0.02:ratio=8[duck]', '[voice][duck]amix=inputs=2:duration=first:normalize=0[aout]']
        cmd += ['-filter_complex',';'.join(filters),'-map',f'[{cur}]','-map','[aout]','-t',str(duration),'-c:v','libx264','-profile:v','high','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k','-ar','48000','-ac','2','-movflags','+faststart',a.out]
        run(cmd); print(f'video={a.out}'); return 0
    except (OSError, ValueError, KeyError, RuntimeError) as e: print(f'error: {e}',file=sys.stderr); return 1
if __name__ == '__main__': sys.exit(main())
