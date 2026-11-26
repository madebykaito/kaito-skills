#!/usr/bin/env python3
"""Check the Kaito short-video delivery profile with ffprobe."""
import argparse, json, os, subprocess, sys

def check(path, target):
    p = subprocess.run([os.environ.get('FFPROBE_BIN', 'ffprobe'), '-v', 'error', '-show_format', '-show_streams', '-of', 'json', path], capture_output=True, text=True, check=True)
    info = json.loads(p.stdout)
    streams = info['streams']
    v = next((s for s in streams if s['codec_type'] == 'video'), None)
    a = next((s for s in streams if s['codec_type'] == 'audio'), None)
    errors = []
    if not v or v.get('codec_name') != 'h264' or v.get('profile') != 'High': errors.append('video must be H.264 High')
    if not v or (v.get('width'), v.get('height')) != (1080, 1920): errors.append('video must be 1080x1920')
    if not a or a.get('codec_name') != 'aac' or a.get('sample_rate') != '48000' or a.get('channels') != 2: errors.append('audio must be stereo AAC at 48 kHz')
    if 'mp4' not in info['format'].get('format_name', '').split(','): errors.append('container must be MP4')
    duration = float(info['format'].get('duration', 0))
    limits = {'ig-reels': (3, 900), 'yt-shorts': (0, 180), 'linkedin': (3, 900)}
    lo, hi = limits[target]
    if not lo <= duration <= hi or duration <= 0: errors.append(f'duration must be {lo} to {hi} seconds')
    # Inspect top-level boxes, rather than searching bytes inside media payloads.
    with open(path, 'rb') as f:
        moov = mdat = None
        while True:
            pos = f.tell(); header = f.read(8)
            if len(header) < 8: break
            size = int.from_bytes(header[:4], 'big'); kind = header[4:]
            if size == 1: size = int.from_bytes(f.read(8), 'big')
            if size == 0: break
            if size < 8: break
            if kind == b'moov': moov = pos
            if kind == b'mdat': mdat = pos
            f.seek(pos + size)
    if moov is None or mdat is None or moov > mdat: errors.append('MP4 moov must precede mdat')
    return errors

def main():
    p = argparse.ArgumentParser(); p.add_argument('command', choices=['check']); p.add_argument('file'); p.add_argument('--target', required=True, choices=['ig-reels','yt-shorts','linkedin']); a = p.parse_args()
    try:
        errors = check(a.file, a.target)
        if errors:
            print('\n'.join(errors), file=sys.stderr); return 1
        print(f'pass: {a.target}'); return 0
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as e:
        print(f'error: {e}', file=sys.stderr); return 1
if __name__ == '__main__': sys.exit(main())
