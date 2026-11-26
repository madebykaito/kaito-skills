#!/usr/bin/env python3
"""Captions: a transparent PNG caption track from timed parts, and transcripts of existing video.

  captions.py render --parts parts.json --out-dir DIR [--y 1380] [--height 360] [--font-size 64]
                     [--font-family CSS] [--color #fff] [--stroke #000] [--max-words N] [--lead 0]
                     [--first-input 1] [--base-label 0:v] [--test-text TEXT]
  captions.py transcribe --video FILE --out-dir DIR [--model PATH] [--lang auto]

render draws one 1080-wide PNG per caption through headless Chrome, so Bengali and other Indic
conjuncts are shaped by a real text engine. It writes DIR/cap00.png ..., DIR/blank.png, DIR/captions.json
(start, end, file), DIR/concat.txt (an ffconcat list of the whole track, gaps are blank.png),
DIR/overlay.filter and DIR/overlay.args (an ffmpeg overlay chain and its -i inputs).
Env: CHROME (browser binary), WHISPER_CPP (whisper-cli path or its folder), WHISPER_MODEL (ggml model).
Exit codes: 0 ok, 1 error, 2 usage, 4 Chrome or whisper.cpp not found.
Python 3 standard library and ffmpeg only.
"""
import argparse
import html
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

WIDTH = 1080
MAC_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FONTS = ("'Noto Sans Bengali','Noto Sans Devanagari','Noto Sans Tamil','Noto Sans Telugu','Kohinoor Bangla',"
         "'Bangla Sangam MN','Kohinoor Devanagari','Kohinoor Tamil','Kohinoor Telugu','Helvetica Neue',Arial,sans-serif")


class Fail(Exception):
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


def find_chrome():
    c = os.environ.get("CHROME")
    if c:
        if os.path.exists(c) or shutil.which(c):
            return c
        raise Fail(f"CHROME={c} does not exist. Point CHROME at a Chrome or Chromium binary.", 4)
    for p in (MAC_CHROME, "/Applications/Chromium.app/Contents/MacOS/Chromium",
              "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
              "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"):
        if os.path.exists(p):
            return p
    for n in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "chrome"):
        if shutil.which(n):
            return shutil.which(n)
    home = pathlib.Path.home()
    for pat in (".cache/puppeteer/chrome-headless-shell/*/*/chrome-headless-shell",
                "Library/Caches/ms-playwright/chromium_headless_shell-*/*/chrome-headless-shell"):
        found = sorted(home.glob(pat))
        if found:
            return str(found[-1])
    raise Fail("Chrome not found. Install Google Chrome or Chromium, or set CHROME to its binary.", 4)


PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;padding:0;background:transparent;width:%(w)dpx;height:%(h)dpx;overflow:hidden}
body{display:flex;align-items:center;justify-content:center}
p{margin:0;padding:0 48px;width:100%%;box-sizing:border-box;text-align:center;color:%(color)s;
font-family:%(family)s;font-weight:700;font-size:%(size)dpx;line-height:1.35;
-webkit-text-stroke:%(sw)dpx %(stroke)s;paint-order:stroke fill;
text-shadow:0 4px 18px rgba(0,0,0,.45)}
</style></head><body><p>%(text)s</p></body></html>"""


STYLE_OK = re.compile(r"^[^<>{};\\]*$")


def render_png(chrome, text, out, a, tmp):
    page = pathlib.Path(tmp) / (out.stem + ".html")
    page.write_text(PAGE % {"w": WIDTH, "h": a.height, "color": a.color, "family": a.font_family, "size": a.font_size,
                            "stroke": a.stroke, "sw": a.stroke_width, "text": html.escape(text)}, encoding="utf-8")
    shot = pathlib.Path(tmp) / (out.stem + ".shot.png")
    cmd = [chrome, "--headless", "--disable-gpu", "--no-sandbox", "--no-first-run", "--disable-background-networking",
           "--disable-component-update", "--hide-scrollbars", "--force-device-scale-factor=1",
           "--default-background-color=00000000", f"--window-size={WIDTH},{a.height}", f"--user-data-dir={tmp}/profile",
           "--virtual-time-budget=3000", f"--screenshot={shot}", page.as_uri()]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if not shot.exists() or shot.stat().st_size == 0:
        raise Fail(f"Chrome made no screenshot: {(r.stderr or r.stdout).strip()[-300:]}")
    shutil.move(str(shot), str(out))  # only a fresh render replaces the old file


def load_parts(path):
    try:
        data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise Fail(f"cannot read parts file: {e}", 2)
    lines = data.get("lines") if isinstance(data, dict) else data
    total = data.get("duration") if isinstance(data, dict) else None
    if not isinstance(lines, list) or not lines:
        raise Fail("parts file has no \"lines\"", 2)
    out = []
    for i, ln in enumerate(lines):
        if not isinstance(ln, dict):
            raise Fail(f"line {i} must be an object with text, start and end", 2)
        try:
            if not isinstance(ln.get("caption") or ln["text"], str):
                raise ValueError("text")
            out.append({"text": (ln.get("caption") or ln["text"]).strip(), "start": float(ln["start"]),
                        "end": float(ln["end"])})
        except (KeyError, TypeError, ValueError):
            raise Fail(f"line {i} needs text, start and end", 2)
    return out, (float(total) if isinstance(total, (int, float)) else None)


def split_words(caps, n):
    """Split each caption into chunks of at most n words; time is shared by character count."""
    if n <= 0:
        return caps
    out = []
    for c in caps:
        w = c["text"].split()
        chunks = [" ".join(w[i:i + n]) for i in range(0, len(w), n)] or [c["text"]]
        total = sum(len(x) for x in chunks) or 1
        t = c["start"]
        for x in chunks:
            d = (c["end"] - c["start"]) * len(x) / total
            out.append({"text": x, "start": round(t, 3), "end": round(t + d, 3)})
            t += d
    return out


def cmd_render(a):
    total = None
    if a.test_text:
        caps = [{"text": a.test_text, "start": 0.0, "end": 2.0}]
    else:
        if not a.parts:
            raise Fail("render needs --parts or --test-text", 2)
        caps, total = load_parts(a.parts)
        caps = split_words(caps, a.max_words)
    for name in ("font_family", "color", "stroke"):
        if not STYLE_OK.match(getattr(a, name)):
            raise Fail(f"--{name.replace('_', '-')} must be a plain CSS value (no < > {{ }} ; or backslash)", 2)
    chrome = find_chrome()
    out = pathlib.Path(a.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    items = []
    with tempfile.TemporaryDirectory() as tmp:
        for i, c in enumerate(caps):
            f = out / f"cap{i:02d}.png"
            render_png(chrome, c["text"], f, a, tmp)
            items.append({"index": i, "text": c["text"], "start": round(c["start"] + a.lead, 3),
                          "end": round(c["end"] + a.lead, 3), "file": f.name})
        render_png(chrome, " ", out / "blank.png", a, tmp)
    # ffconcat list of the whole track: captions at their times, blank.png in the gaps
    rows, t = ["ffconcat version 1.0"], 0.0
    for it in items:
        if it["end"] <= 0:  # shifted entirely before the video
            continue
        a0 = max(it["start"], t, 0.0)
        b0 = max(it["end"], a0 + 0.04)  # a frame at least, so the list never runs ahead of the times
        if a0 > t + 0.0005:
            rows += ["file blank.png", f"duration {a0 - t:.3f}"]
        rows += [f"file {it['file']}", f"duration {b0 - a0:.3f}"]
        t = b0
    end = total if total is not None else t
    if end > t + 0.0005:
        rows += ["file blank.png", f"duration {end - t:.3f}"]  # the voice's trailing pause
    rows += ["file blank.png"]  # ffconcat ignores the last duration unless the file repeats
    (out / "concat.txt").write_text("\n".join(rows) + "\n")
    # overlay chain: inputs are the PNGs, appended after the base input(s) the other skill already has
    flt, prev = [], a.base_label if a.base_label.startswith("[") else f"[{a.base_label}]"
    args = []
    for j, it in enumerate(items):
        args += ["-i", str((out / it["file"]))]
        last = j == len(items) - 1
        lab = "[vout]" if last else f"[c{j}]"
        flt.append(f"{prev}[{a.first_input + j}:v]overlay=0:{a.y}:enable='gte(t,{it['start']:.3f})*lt(t,{it['end']:.3f})'{lab}")
        prev = lab
    (out / "overlay.filter").write_text(";\n".join(flt) + "\n")
    (out / "overlay.args").write_text("\n".join(args) + "\n")
    (out / "captions.json").write_text(json.dumps({"version": 1, "width": WIDTH, "height": a.height, "y": a.y,
                                                   "captions": items}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"captions={out / 'captions.json'}")
    print(f"count={len(items)}")
    return 0


def find_whisper():
    w = os.environ.get("WHISPER_CPP")
    if w:
        p = pathlib.Path(w)
        if p.is_dir():
            for n in ("whisper-cli", "main"):
                if (p / n).is_file() or (p / "build/bin" / n).is_file():
                    return str(p / n) if (p / n).is_file() else str(p / "build/bin" / n)
        elif p.is_file():
            return str(p)
        raise Fail(f"WHISPER_CPP={w} is not a whisper-cli binary or a folder holding one.", 4)
    return shutil.which("whisper-cli")


INSTALL = ("whisper.cpp is not installed. Install it: brew install whisper-cpp (gives whisper-cli), or build it from "
           "github.com/ggml-org/whisper.cpp and set WHISPER_CPP to the whisper-cli binary. Then download a model, "
           "for example ggml-small.bin from huggingface.co/ggerganov/whisper.cpp, and set WHISPER_MODEL to its path.")


def cmd_transcribe(a):
    exe = find_whisper()
    if not exe:
        raise Fail(INSTALL, 4)
    model = a.model or os.environ.get("WHISPER_MODEL")
    if not model or not os.path.isfile(model):
        raise Fail("whisper model not found. Pass --model or set WHISPER_MODEL to a ggml model file "
                   "(for example ggml-small.bin from huggingface.co/ggerganov/whisper.cpp).", 4)
    if not os.path.isfile(a.video):
        raise Fail(f"video not found: {a.video}", 2)
    if not shutil.which("ffmpeg"):
        raise Fail("ffmpeg not found. Install ffmpeg (brew install ffmpeg).", 4)
    out = pathlib.Path(a.out_dir).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for old in ("whisper.json", "whisper.srt", "transcript.json"):
        (out / old).unlink(missing_ok=True)  # never report an older run's files as this run's
    with tempfile.TemporaryDirectory(prefix="captions-") as scratch:
        wav = pathlib.Path(scratch) / "audio16k.wav"
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", a.video, "-vn", "-ac", "1", "-ar", "16000", str(wav)],
                           capture_output=True, text=True)
        if r.returncode != 0:
            raise Fail(f"ffmpeg could not read the audio: {r.stderr.strip()[-300:]}")
        prefix = pathlib.Path(scratch) / "whisper"
        r = subprocess.run([exe, "-m", model, "-f", str(wav), "-l", a.lang, "-oj", "-osrt", "-of", str(prefix)],
                           capture_output=True, text=True)
        jf = pathlib.Path(str(prefix) + ".json")
        if r.returncode != 0 or not jf.exists():
            raise Fail(f"whisper-cli failed: {(r.stderr or r.stdout).strip()[-300:]}")
        try:
            segs = json.loads(jf.read_text(encoding="utf-8")).get("transcription", [])
        except ValueError:
            raise Fail("whisper-cli wrote JSON that could not be read")
        srt = pathlib.Path(str(prefix) + ".srt")
        if srt.exists():
            shutil.copyfile(srt, out / "whisper.srt")
    lines = []
    for s_ in segs:
        text = s_.get("text", "").strip()
        if not text:
            continue
        lines.append({"index": len(lines), "text": text, "start": round(s_["offsets"]["from"] / 1000, 3),
                      "end": round(s_["offsets"]["to"] / 1000, 3), "file": None})
    parts = out / "transcript.json"
    parts.write_text(json.dumps({"version": 1, "engine": "whisper.cpp", "source": os.path.basename(a.video),
                                 "lines": lines}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"transcript={parts}")
    if (out / "whisper.srt").exists():
        print(f"srt={out / 'whisper.srt'}")
    print(f"count={len(lines)}")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    r.add_argument("--parts")
    r.add_argument("--out-dir", required=True)
    r.add_argument("--test-text")
    r.add_argument("--y", type=int, default=1380, help="top of the caption box in the video frame")
    r.add_argument("--height", type=int, default=360)
    r.add_argument("--font-size", type=int, default=64)
    r.add_argument("--font-family", default=FONTS)
    r.add_argument("--color", default="#ffffff")
    r.add_argument("--stroke", default="#000000")
    r.add_argument("--stroke-width", type=int, default=6)
    r.add_argument("--max-words", type=int, default=0)
    r.add_argument("--lead", type=float, default=0.0, help="seconds added to every start and end")
    r.add_argument("--first-input", type=int, default=1, help="ffmpeg input index of the first PNG in overlay.filter")
    r.add_argument("--base-label", default="0:v")
    t = sub.add_parser("transcribe")
    t.add_argument("--video", required=True)
    t.add_argument("--out-dir", required=True)
    t.add_argument("--model")
    t.add_argument("--lang", default="auto")
    a = ap.parse_args(argv)
    try:
        return cmd_render(a) if a.cmd == "render" else cmd_transcribe(a)
    except Fail as e:
        print(f"error: {e}", file=sys.stderr)
        return e.code
    except subprocess.TimeoutExpired:
        print("error: a subprocess timed out", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
