#!/usr/bin/env python3
"""Voiceover: one TTS request per line, trim, breaths, loudnorm, timed parts.

Usage: voiceover.py --lines lines.json --out-dir DIR [--engine svara|parler|sarvam] [--owner ID]
                    [--voice NAME] [--language CODE] [--cloud-ok] [--lufs -16] [--breath 0.12]

lines.json: {"language": "bn-IN", "voice": "...", "lines": [{"text": "...", "tone": "warm", "pause_after": 0.3}]}
(a bare list of lines also works). Writes DIR/voice.wav (48 kHz mono, -16 LUFS), DIR/lines/lineNN.wav
and DIR/parts.json. Exit codes: 0 ok, 1 error, 2 usage, 3 needs consent, 4 engine not found.
Python 3 standard library and ffmpeg only.
"""
import argparse
import base64
import json
import math
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import urllib.request

SR = 48000
TRIM = ("silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
        "silenceremove=start_periods=1:start_threshold=-45dB,areverse")
SVARA_MODEL = "kenpath/svara-tts-v1"
PARLER_MODEL = "ai4bharat/indic-parler-tts"
SARVAM_API = "https://api.sarvam.ai/text-to-speech"
HOME = pathlib.Path(os.environ.get("HOME") or str(pathlib.Path.home()))

# svara has no tone control (emotion tags made generation hang), so tone only reaches parler and sarvam.
PARLER_TONE = {
    "neutral": "speaks in a clear, even tone",
    "warm": "speaks in a warm, friendly tone",
    "excited": "speaks in an excited, energetic tone, slightly fast",
    "calm": "speaks in a calm, soft, unhurried tone",
    "serious": "speaks in a serious, measured tone",
}
SARVAM_TONE = {  # pitch, pace, loudness
    "neutral": (0, 1.0, 1.0),
    "warm": (0.05, 1.0, 1.0),
    "excited": (0.1, 1.2, 1.1),
    "calm": (-0.05, 0.9, 0.95),
    "serious": (-0.1, 0.95, 1.0),
}
SVARA_VOICE = {"bn": "Bengali (Female)", "en": "English (India) (Female)", "hi": "Hindi (Female)"}


class Fail(Exception):
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


def run(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise Fail(f"{os.path.basename(cmd[0])} failed: {(r.stderr or r.stdout).strip()[-400:]}")
    return r


EMOTION_TAG = re.compile(r"<[^<>\n]{1,24}>")
OWNER_ID = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")


def run_engine(cmd, module, **kw):
    """Like run, but a python without the engine's package is 'not found' (exit 4), not a crash."""
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        err = (r.stderr or r.stdout)
        if "No module named" in err:
            raise Fail(f"{module} is not installed in {cmd[0]}. Install it there or point the engine variable at another python.", 4)
        raise Fail(f"{os.path.basename(cmd[0])} failed: {err.strip()[-400:]}")
    return r


def need_ffmpeg():
    for t in ("ffmpeg", "ffprobe"):
        if not shutil.which(t):
            raise Fail(f"{t} not found. Install ffmpeg (brew install ffmpeg).", 4)


def duration(path):
    r = run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)])
    return float(r.stdout.strip())


def load_lines(path):
    try:
        spec = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise Fail(f"cannot read lines file: {e}", 2)
    if isinstance(spec, list):
        spec = {"lines": spec}
    if not isinstance(spec, dict):
        raise Fail("lines file must be a JSON object or a list", 2)
    lines = spec.get("lines")
    if not isinstance(lines, list) or not lines:
        raise Fail("lines file needs a non-empty \"lines\" list", 2)
    out = []
    for i, ln in enumerate(lines):
        if isinstance(ln, str):
            ln = {"text": ln}
        if not isinstance(ln, dict) or not isinstance(ln.get("text"), str) or not ln["text"].strip():
            raise Fail(f"line {i} needs a text string", 2)
        try:
            pause = float(ln.get("pause_after", 0.3))
        except (TypeError, ValueError):
            raise Fail(f"line {i}: pause_after must be a number", 2)
        if not 0 <= pause <= 10:
            raise Fail(f"line {i}: pause_after must be between 0 and 10 seconds", 2)
        text = EMOTION_TAG.sub("", ln["text"]).strip()  # unspoken tags must not reach the engine or the captions
        if not text:
            raise Fail(f"line {i} has no text after removing tags", 2)
        out.append({"text": text, "tone": str(ln.get("tone", "neutral")), "pause_after": pause})
    for k in ("language", "voice"):
        if spec.get(k) is not None and not isinstance(spec[k], str):
            raise Fail(f"{k} must be a string", 2)
    return spec, out


def loudnorm_filter(path, lufs):
    """Two passes: measure, then a linear correction. Falls back to one pass if the measurement cannot be read."""
    base = f"loudnorm=I={lufs}:TP=-1.5:LRA=11"
    r = subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af", base + ":print_format=json",
                        "-f", "null", "-"], capture_output=True, text=True)
    try:
        m = json.loads(r.stderr[r.stderr.rindex("{"):r.stderr.rindex("}") + 1])
        vals = [float(m[k]) for k in ("input_i", "input_tp", "input_lra", "input_thresh", "target_offset")]
    except (ValueError, KeyError):
        return base
    if not all(math.isfinite(v) for v in vals):  # a very short or silent clip measures as -inf
        return base
    return (f"{base}:measured_I={vals[0]}:measured_TP={vals[1]}:measured_LRA={vals[2]}:"
            f"measured_thresh={vals[3]}:offset={vals[4]}:linear=true")


def lang_key(code):
    return (code or "bn-IN").split("-")[0].lower()


# ---- engines: each returns a path to a raw wav for one line ----

def svara_line(text, tone, a, tmp, i):
    py = os.environ.get("SVARA_PYTHON", str(HOME / "AI-Tools/tts/mlx/bin/python"))
    if not os.path.exists(py) and not shutil.which(py):
        raise Fail(f"svara python not found at {py}. Set SVARA_PYTHON to a python with mlx-audio installed.", 4)
    voice = a.voice or SVARA_VOICE.get(lang_key(a.language), "Bengali (Female)")
    run_engine([py, "-m", "mlx_audio.tts.generate", "--model", SVARA_MODEL, "--voice", voice, "--text", text,
                "--output_path", tmp, "--file_prefix", f"l{i}", "--audio_format", "wav", "--max_tokens", "1200"],
               "mlx_audio", timeout=600)
    raw = pathlib.Path(tmp) / f"l{i}_000.wav"
    if not raw.exists():
        raise Fail(f"svara wrote no audio for line {i}")
    return raw


PARLER_RUNNER = r'''
import sys, torch, soundfile as sf
from transformers import AutoTokenizer
from parler_tts import ParlerTTSForConditionalGeneration
model_id, text, desc, out = sys.argv[1:5]
dev = "mps" if torch.backends.mps.is_available() else "cpu"
model = ParlerTTSForConditionalGeneration.from_pretrained(model_id).to(dev)
tok = AutoTokenizer.from_pretrained(model_id)
dtok = AutoTokenizer.from_pretrained(model.config.text_encoder._name_or_path)
d = dtok(desc, return_tensors="pt").to(dev)
p = tok(text, return_tensors="pt").to(dev)
audio = model.generate(input_ids=d.input_ids, attention_mask=d.attention_mask,
                       prompt_input_ids=p.input_ids, prompt_attention_mask=p.attention_mask)
sf.write(out, audio.cpu().numpy().squeeze(), model.config.sampling_rate)
'''


def parler_line(text, tone, a, tmp, i):
    root = pathlib.Path(os.environ.get("PARLER_HOME", str(HOME / "AI-Tools/tts/parler")))
    py = os.environ.get("PARLER_PYTHON", str(root / "bin/python"))
    if not os.path.exists(py) and not shutil.which(py):
        raise Fail(f"parler python not found at {py}. Set PARLER_PYTHON or PARLER_HOME.", 4)
    speaker = a.voice or "Aditi"
    desc = (f"{speaker} {PARLER_TONE.get(tone, PARLER_TONE['neutral'])}, with very clear audio and no background noise, "
            "close to the microphone.")
    out = pathlib.Path(tmp) / f"l{i}.wav"
    run_engine([py, "-c", PARLER_RUNNER, os.environ.get("PARLER_MODEL", PARLER_MODEL), text, desc, str(out)],
               "parler_tts", timeout=900)
    return out


def sarvam_key(owner):
    if not OWNER_ID.match(owner or ""):
        raise Fail("--owner must be an owner id such as lumen-tea", 2)
    f = HOME / ".config" / "sarvam" / f"{owner}.env"
    if not f.is_file():
        raise Fail(f"no Sarvam key file for owner {owner}: expected {f}", 4)
    for raw in f.read_text().splitlines():
        k, _, v = raw.partition("=")
        if k.strip() in ("SARVAM_API_KEY", "SARVAM_KEY") and v.strip():
            return v.strip().strip("'\"")
    raise Fail(f"{f} has no SARVAM_API_KEY line", 4)


def check_consent(a):
    """Sarvam is a cloud service: the text leaves this machine. Needs the owner's consent."""
    if not a.owner or not OWNER_ID.match(a.owner):
        raise Fail("sarvam needs --owner <id>, such as lumen-tea (its key file and consent are per owner)", 2)
    here = pathlib.Path(__file__).resolve()
    kh = pathlib.Path(os.environ.get("KAITO_HOME", str(HOME / ".kaito")))
    for base in (kh / "store", here.parents[2]):
        eng = base / "business/scripts/kaito-engines.mjs"
        if eng.is_file():
            if not shutil.which("node"):
                raise Fail("node not found, cannot check cloud consent", 4)
            r = subprocess.run(["node", str(eng), "consent", "sarvam", "--owner", a.owner, "--status"],
                               capture_output=True, text=True)
            # the tool exits 0 for both answers and prints "... granted" or "... not granted"
            if r.returncode == 0 and re.search(r":\s*granted\s*$", r.stdout.strip()):
                return
            raise Fail("cloud consent for sarvam not given: " + (r.stdout + r.stderr).strip()[-300:], 3)
    if a.cloud_ok:
        return
    raise Fail("sarvam is a cloud engine and sends the script text to Sarvam. No consent tool is installed; "
               "pass --cloud-ok only if the owner agreed.", 3)


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kw):  # the key header must never follow a redirect
        return None


NO_REDIRECT = urllib.request.build_opener(_NoRedirect)


def sarvam_url():
    """The key and script go only to Sarvam. SARVAM_API may point at a local stub (tests), nowhere else."""
    u = os.environ.get("SARVAM_API")
    if u and urllib.parse.urlparse(u).hostname in ("127.0.0.1", "localhost", "::1"):
        return u
    return SARVAM_API


def sarvam_line(text, tone, a, tmp, i):
    key = a.sarvam_key
    pitch, pace, loud = SARVAM_TONE.get(tone, SARVAM_TONE["neutral"])
    body = {"text": text, "language_code": a.language, "model": os.environ.get("SARVAM_MODEL", "bulbul:v4-flash"),
            "speaker": a.voice or "roopa_bn_conversational", "pitch": pitch, "pace": pace, "loudness": loud,
            "speech_sample_rate": 44100, "output_audio_codec": "wav"}
    req = urllib.request.Request(sarvam_url(), data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "api-subscription-key": key})
    try:
        with NO_REDIRECT.open(req, timeout=120) as r:
            audio = base64.b64decode(json.load(r)["audios"][0])
    except Exception as e:  # never echo the request: it carries the key header
        raise Fail(f"sarvam request failed for line {i}: {type(e).__name__}")
    raw = pathlib.Path(tmp) / f"l{i}.wav"
    raw.write_bytes(audio)
    return raw


ENGINES = {"svara": svara_line, "parler": parler_line, "sarvam": sarvam_line}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--lines", required=True)
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--engine", choices=sorted(ENGINES), default="svara")
    ap.add_argument("--owner")
    ap.add_argument("--voice")
    ap.add_argument("--language")
    ap.add_argument("--cloud-ok", action="store_true")
    ap.add_argument("--lufs", type=float, default=-16.0)
    ap.add_argument("--breath", type=float, default=0.12, help="seconds of room before each line")
    a = ap.parse_args(argv)
    try:
        spec, lines = load_lines(a.lines)
        a.language = a.language or spec.get("language") or "bn-IN"
        a.voice = a.voice or spec.get("voice")
        if a.engine == "sarvam":  # consent first: nothing else runs for a refused cloud call
            check_consent(a)
            a.sarvam_key = sarvam_key(a.owner)
        need_ffmpeg()
        out = pathlib.Path(a.out_dir).resolve()
        (out / "lines").mkdir(parents=True, exist_ok=True)
        gen = ENGINES[a.engine]
        parts, t = [], 0.0
        with tempfile.TemporaryDirectory() as tmp:
            for i, ln in enumerate(lines):
                raw = gen(ln["text"], ln["tone"], a, tmp, i)
                wav = out / "lines" / f"line{i:02d}.wav"
                # speech trimmed at both ends, a short breath before it, the pause after it
                af = f"{TRIM},adelay={int(a.breath * 1000)}:all=1,apad=pad_dur={ln['pause_after']}"
                run(["ffmpeg", "-v", "error", "-y", "-i", str(raw), "-af", af, "-ar", str(SR), "-ac", "1", str(wav)])
                d = duration(wav)
                speech_end = max(d - ln["pause_after"], a.breath)
                parts.append({"index": i, "text": ln["text"], "tone": ln["tone"],
                              "start": round(t + a.breath, 3), "end": round(t + speech_end, 3),
                              "pause_after": ln["pause_after"], "clip_start": round(t, 3),
                              "clip_end": round(t + d, 3), "file": f"lines/line{i:02d}.wav", "duration": round(d, 3)})
                t += d
        lst = out / "lines" / "concat.txt"
        lst.write_text("".join(f"file 'line{p['index']:02d}.wav'\n" for p in parts))  # relative to the list
        joined = out / "lines" / "joined.wav"
        run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", str(joined)])
        voice = out / "voice.wav"
        run(["ffmpeg", "-v", "error", "-y", "-i", str(joined), "-af", loudnorm_filter(joined, a.lufs),
             "-ar", str(SR), "-ac", "1", str(voice)])
        joined.unlink()
        lst.unlink()
        meta = {"version": 1, "engine": a.engine, "voice_name": a.voice, "language": a.language, "sample_rate": SR,
                "lufs": a.lufs, "voice": "voice.wav", "duration": round(duration(voice), 3), "lines": parts}
        (out / "parts.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"voice={voice}")
        print(f"parts={out / 'parts.json'}")
        print(f"duration={meta['duration']}")
        return 0
    except Fail as e:
        print(f"error: {e}", file=sys.stderr)
        return e.code


if __name__ == "__main__":
    sys.exit(main())
