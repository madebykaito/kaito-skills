#!/usr/bin/env python3
"""Instrumental music beds with ACE-Step through ComfyUI. Python 3 standard library only.

  music.py --style "warm lo-fi, soft keys" --seconds 30 --takes 3 --out-dir DIR

Each take gets its own style tags and seed, and is written as a 48 kHz stereo WAV with a sidecar JSON.
Runs through the shared ComfyUI client in local-video/scripts/comfy.py: one heavy model at a time,
/free before and after, refuses to start when free memory is below the need (exit 3).
Exit codes: 0 ok, 1 error, 2 usage, 3 needs a human decision (low memory, lock timeout), 4 not found (engine, ComfyUI, ffmpeg).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(os.path.dirname(HERE), "workflows", "acestep_instrumental.json")
SAMPLE_RATE = 48000

# Style modifiers added to the base style, one per take, in order. Twelve takes is the cap, so none repeats.
VARIANTS = [
    "",
    "warm analog pads, soft felt piano, slow and spacious",
    "plucked strings, light percussion, airy and hopeful",
    "deep sub bass, ambient textures, slowly evolving",
    "acoustic guitar, brushed drums, organic and warm",
    "mellow electric piano, lo-fi drums, relaxed groove",
    "cinematic strings, gentle swells, subtle low drums",
    "soft synth arpeggios, warm bass, dreamy and slow",
    "kalimba and marimba, light shakers, playful",
    "dusty piano, upright bass, soft brushed snare, late night",
    "glassy bells, wide reverb, minimal and calm",
    "warm cello, sparse piano, tender and reflective",
]
SEED_STEP = 7919


def _load_comfy():
    here = os.path.join(os.path.dirname(os.path.dirname(HERE)), "local-video", "scripts")
    kaito = os.environ.get("KAITO_HOME") or os.path.join(os.path.expanduser("~"), ".kaito")
    for d in (here, os.path.join(kaito, "store", "local-video", "scripts")):
        if os.path.isfile(os.path.join(d, "comfy.py")):
            sys.path.insert(0, d)
            import comfy
            return comfy
    print("error: music needs the local-video skill (its scripts/comfy.py). Install both skills.", file=sys.stderr)
    sys.exit(4)


comfy = _load_comfy()


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def plan_takes(style, takes, seed, bpm, key, variants=None):
    pool = variants or VARIANTS
    if len(pool) < takes:
        raise comfy.Usage(f"--variants has {len(pool)} styles for {takes} takes; give at least one per take")
    out = []
    for i in range(takes):
        mod = pool[i % len(pool)]
        tags = ", ".join(x for x in (style, mod, "instrumental, no vocals") if x)
        out.append({"take": i + 1, "tags": tags, "style_variant": mod, "seed": seed + i * SEED_STEP, "bpm": bpm, "key": key})
    return out


def wav_info(path):
    try:
        with wave.open(path, "rb") as w:
            return {"sample_rate": w.getframerate(), "channels": w.getnchannels(), "width": w.getsampwidth(), "seconds": round(w.getnframes() / float(w.getframerate()), 2)}
    except (wave.Error, EOFError):
        return None


def to_wav48(src, dst):
    """48 kHz stereo 16-bit WAV. A file that already is one is copied."""
    info = wav_info(src)
    if info and info["sample_rate"] == SAMPLE_RATE and info["channels"] == 2 and info["width"] == 2:
        shutil.copyfile(src, dst)
        return
    if not shutil.which("ffmpeg"):
        raise comfy.Missing("ffmpeg is not installed (brew install ffmpeg); it converts ACE-Step's FLAC to a 48 kHz WAV")
    r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", src, "-ar", str(SAMPLE_RATE), "-ac", "2", "-c:a", "pcm_s16le", dst], capture_output=True, text=True)
    if r.returncode != 0:
        raise comfy.ComfyError("ffmpeg failed: " + r.stderr.strip()[-600:])


def build_parser():
    ap = argparse.ArgumentParser(prog="music.py", description=__doc__.split("\n\n")[0])
    ap.add_argument("--style", default="calm instrumental bed, soft pads", help="base style tags, comma separated")
    ap.add_argument("--seconds", type=float, default=30.0)
    ap.add_argument("--takes", type=int, default=1, help="how many beds; each gets its own style tags and seed")
    ap.add_argument("--variants", help="your own per-take style additions, separated by |; replaces the built-in list")
    ap.add_argument("--bpm", type=int, default=66)
    ap.add_argument("--key", default="D minor")
    ap.add_argument("--seed", type=int, default=7, help="seed of take 1; later takes add %d each" % SEED_STEP)
    ap.add_argument("--steps", type=int, help="sampler steps (template default 8)")
    ap.add_argument("--out-dir", default="music-out")
    ap.add_argument("--name", default="music", help="file name stem: <name>-take1.wav")
    ap.add_argument("--url", help="ComfyUI base URL (default: COMFY_URL, else ports 8188, 8189, 8288)")
    ap.add_argument("--start", action="store_true", help="open Comfy Desktop if no ComfyUI answers (macOS)")
    ap.add_argument("--need-gb", type=float, help="free memory the run needs; below it the run is refused (exit 3)")
    ap.add_argument("--timeout", type=float, default=1800, help="seconds to wait for each take")
    ap.add_argument("--lock-timeout", type=float, default=3600)
    ap.add_argument("--settle", type=float, default=3.0)
    ap.add_argument("--dry-run", action="store_true", help="print the planned takes as JSON and stop")
    return ap


def main(argv):
    a = build_parser().parse_args(argv)
    try:
        if not a.name or a.name in (".", "..") or "/" in a.name or "\\" in a.name:
            raise comfy.Usage("--name must be a file name, not a path")
        if not 5 <= a.seconds <= 240:
            raise comfy.Usage("--seconds must be between 5 and 240")
        if not 1 <= a.takes <= 12:
            raise comfy.Usage("--takes must be between 1 and 12")
        variants = [v.strip() for v in a.variants.split("|")] if a.variants else None
        takes = plan_takes(a.style, a.takes, a.seed, a.bpm, a.key, variants)
        meta, _ = comfy.load_template(TEMPLATE)
        need = comfy.need_gb_for(meta, a.need_gb)
        if a.dry_run:
            print(json.dumps({"seconds": a.seconds, "need_gb": need, "takes": takes}, indent=1))
            return 0
        log("licence: ACE-Step weights are published under an open licence by ACE Studio; check the model card of the checkpoint you use before commercial work.")
        os.makedirs(a.out_dir, exist_ok=True)
        t0 = time.time()

        def preflight(c):
            comfy.resolve_models(c, meta, comfy.coerce(meta, {}))

        results = []
        with comfy.heavy_session(a.url, a.start, need, a.lock_timeout, a.settle, preflight) as c:
            for t in takes:  # the model stays loaded between takes
                log(f"take {t['take']} of {len(takes)}: seed {t['seed']}, {t['tags']}")
                params = {"tags": t["tags"], "seed": t["seed"], "seconds": a.seconds, "bpm": a.bpm, "key": a.key,
                          "steps": a.steps, "prefix": f"audio/{a.name}-take{t['take']}"}
                params = {k: v for k, v in params.items() if v is not None}
                tmp = tempfile.mkdtemp(prefix=".dl-", dir=a.out_dir)
                t1 = time.time()
                res = comfy.run_template(c, TEMPLATE, params, tmp, a.timeout)
                src = next((f["path"] for f in res["files"] if f["kind"] == "audio"), None)
                if not src:
                    raise comfy.ComfyError("ComfyUI finished but returned no audio file")
                dst = os.path.join(a.out_dir, f"{a.name}-take{t['take']}.wav")
                to_wav48(src, dst)
                shutil.rmtree(tmp, ignore_errors=True)
                info = wav_info(dst) or {}
                side = {"tool": "music", "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "engine": "acestep", "model": "ace_step_1.5_turbo",
                        "take": t["take"], "tags": t["tags"], "style_variant": t["style_variant"], "base_style": a.style, "seed": t["seed"],
                        "bpm": a.bpm, "key": a.key, "seconds_requested": a.seconds, "steps": res["params"].get("steps"),
                        "output": os.path.basename(dst), **info, "seconds_elapsed": round(time.time() - t1, 1), "comfy": c.base,
                        "vocals": False}
                with open(dst[:-4] + ".json", "w") as f:
                    json.dump(side, f, indent=1)
                    f.write("\n")
                print(f"take{t['take']}={dst}")
                results.append(dst)
        print(f"seconds={round(time.time() - t0, 1)}")
        return 0
    except comfy.ComfyError as e:
        log(f"error: {e}")
        return e.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
