#!/usr/bin/env python3
"""keyframes: styled stills and same-face stills with local mflux models.

Python 3 standard library only. The engines are external programs:
  mflux-generate-z-image-turbo   still   (Z-Image-Turbo, text to image)
  mflux-generate-flux2-edit      same-face (FLUX.2 klein edit, reference photos in)
  ffmpeg                         upscale or crop to the final size
  a python with dlib and face_recognition (LIKENESS_PYTHON)   score, optional

Exit codes: 0 ok, 1 error, 2 usage, 3 refused (weight license), 4 engine or tool not found.
"""
import argparse
import datetime
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time

# Weight licenses, checked against the Hugging Face model cards on 2026-11-26.
# Refusal is on `commercial`: a weight whose license bars commercial use needs --noncommercial-ok.
MODELS = {
    "z-image-turbo": {
        "repo": "Tongyi-MAI/Z-Image-Turbo",
        "license": "apache-2.0",
        "commercial": True,
        "card": "https://huggingface.co/Tongyi-MAI/Z-Image-Turbo",
        "tool": "mflux-generate-z-image-turbo",
        "kind": "still",
    },
    "flux2-klein-4b": {
        "repo": "black-forest-labs/FLUX.2-klein-4B",
        "license": "apache-2.0",
        "commercial": True,
        "card": "https://huggingface.co/black-forest-labs/FLUX.2-klein-4B",
        "tool": "mflux-generate-flux2-edit",
        "kind": "same-face",
    },
    "flux2-klein-9b": {
        "repo": "black-forest-labs/FLUX.2-klein-9B",
        "license": "flux-non-commercial-license",
        "commercial": False,
        "card": "https://huggingface.co/black-forest-labs/FLUX.2-klein-9B",
        "tool": "mflux-generate-flux2-edit",
        "kind": "same-face",
    },
}
DEFAULT_MODEL = {"still": "z-image-turbo", "same-face": "flux2-klein-4b"}

# name: (generate width, height, final width, height). Generated sizes are multiples of 16.
# 864x1536 times 1.25 is exactly 1080x1920, so a Reel needs no crop.
SIZES = {
    "reel": (864, 1536, 1080, 1920),
    "square": (1024, 1024, 1080, 1080),
    "portrait": (896, 1120, 1080, 1350),
    "landscape": (1344, 768, 1920, 1080),
}

STYLE_CAP = 900


class Fail(Exception):
    def __init__(self, msg, code=1):
        super().__init__(msg)
        self.code = code


def log(msg):
    print(msg, flush=True)


def kaito_home():
    return os.environ.get("KAITO_HOME") or os.path.join(os.path.expanduser("~"), ".kaito")


def bin_dir():
    return os.path.expanduser(os.environ.get("MFLUX_BIN_DIR") or "~/.local/bin")


def find_engine(name):
    path = os.path.join(bin_dir(), name)
    if os.path.isfile(path) and os.access(path, os.X_OK):
        return path
    raise Fail(
        f"engine not found: {path}\n"
        f"Install mflux (uv tool install mflux) or set MFLUX_BIN_DIR to the folder that holds {name}.",
        4,
    )


def find_ffmpeg():
    cand = os.environ.get("FFMPEG_BIN")
    if cand:
        cand = os.path.expanduser(cand)
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
        raise Fail(f"ffmpeg not found: FFMPEG_BIN={cand}", 4)
    return shutil.which("ffmpeg")


def parse_size(spec):
    """Returns (gen_w, gen_h, final_w, final_h). final equals gen for a custom size or when native."""
    s = (spec or "reel").lower()
    if s in SIZES:
        return SIZES[s]
    m = re.fullmatch(r"(\d{3,5})x(\d{3,5})", s)
    if not m:
        raise Fail(f"bad --size '{spec}': use reel, square, portrait, landscape or WIDTHxHEIGHT", 2)
    w, h = int(m.group(1)), int(m.group(2))
    if w < 64 or h < 64:
        raise Fail(f"bad --size '{spec}': each side must be at least 64", 2)
    gw, gh = max(256, int(w / 16 + 0.5) * 16), max(256, int(h / 16 + 0.5) * 16)
    return gw, gh, w, h


def check_license(key, allow_nc):
    m = MODELS[key]
    state = "commercial use allowed" if m["commercial"] else "NOT for commercial use"
    log(f"weights: {m['repo']}  license {m['license']}  {state}  ({m['card']})")
    if not m["commercial"] and not allow_nc:
        raise Fail(
            f"refused: {m['repo']} is licensed {m['license']}, which bars commercial use.\n"
            "Pick a commercial weight, or pass --noncommercial-ok for work that is never sold or posted for a business.",
            3,
        )


def read_style(path):
    """Brand style file to prompt text. Uses the first section whose heading names image, visual, photo or style; else the whole file."""
    try:
        with open(os.path.expanduser(path), encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        raise Fail(f"cannot read --style-file: {e}", 1)
    sections = re.split(r"(?m)^#{1,6}\s+", text)
    heads = re.findall(r"(?m)^#{1,6}\s+(.*)$", text)
    pick = None
    for head, body in zip(heads, sections[1:]):
        if re.search(r"image|visual|photo|style|look", head, re.I):
            pick = body.split("\n", 1)[1] if "\n" in body else ""
            break
    if pick is None:
        pick = text
    pick = re.sub(r"(?m)^\s*(#+|[-*]|\d+\.)\s*", "", pick)
    pick = re.sub(r"\s+", " ", pick).strip()
    return pick[:STYLE_CAP]


def read_prompt(a):
    if a.prompt_file:
        try:
            with open(os.path.expanduser(a.prompt_file), encoding="utf-8") as f:
                p = f.read().strip()
        except OSError as e:
            raise Fail(f"cannot read --prompt-file: {e}", 1)
    else:
        p = (a.prompt or "").strip()
    if not p:
        raise Fail("a prompt is required: --prompt or --prompt-file", 2)
    if p == "-":
        raise Fail("a prompt of '-' is not allowed (the engine would read stdin)", 2)
    return p


def part(value, what):
    """One path component: letters, digits, dot, dash, underscore. No separators, no '..'."""
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", value or "") or ".." in value:
        raise Fail(f"bad {what} '{value}': use letters, digits, dot, dash or underscore (use --out-dir for a folder)", 2)
    return value


def out_dir(a):
    if a.out_dir:
        return os.path.expanduser(a.out_dir)
    if a.owner:
        return os.path.join(kaito_home(), "owners", part(a.owner, "--owner"), "studio", part(a.job, "--job"))
    return os.path.join(os.getcwd(), "keyframes-out")


def slug(text):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return "-".join(s.split("-")[:6]) or "frame"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd):
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    except OSError as e:
        raise Fail(f"could not start {cmd[0]}: {e}", 4)
    if r.returncode != 0:
        tail = "\n".join(r.stdout.strip().splitlines()[-12:])
        raise Fail(f"{os.path.basename(cmd[0])} failed with exit {r.returncode}\n{tail}", 1)
    return r.stdout


def to_final(native, final, fw, fh, ffmpeg):
    """Scale to cover fw x fh, then crop the overflow, in one ffmpeg call."""
    vf = f"scale={fw}:{fh}:force_original_aspect_ratio=increase:flags=lanczos,crop={fw}:{fh}"
    run([ffmpeg, "-y", "-loglevel", "error", "-i", native, "-vf", vf, "-frames:v", "1", final])


def generate(a, kind):
    key = a.model or DEFAULT_MODEL[kind]
    if key not in MODELS or MODELS[key]["kind"] != kind:
        ok = ", ".join(k for k, v in MODELS.items() if v["kind"] == kind)
        raise Fail(f"model '{key}' is not pinned for {kind}. Pinned: {ok}", 2)
    gw, gh, fw, fh = parse_size(a.size)
    check_license(key, a.noncommercial_ok)
    user_prompt = read_prompt(a)
    style = read_style(a.style_file) if a.style_file else ""
    refs = []
    if kind == "same-face":
        refs = [os.path.abspath(os.path.expanduser(r)) for r in a.ref]
        for r in refs:
            if not os.path.isfile(r):
                raise Fail(f"reference not found: {r}", 4)
    parts = []
    if kind == "same-face" and not a.no_prefix:
        parts.append("The same person as in the reference image.")
    parts.append(user_prompt)
    if style:
        parts.append(style)
    prompt = " ".join(parts)

    engine = find_engine(MODELS[key]["tool"])
    native_only = a.native or (fw, fh) == (gw, gh)
    ffmpeg = None
    if not native_only:
        ffmpeg = find_ffmpeg()
        if not ffmpeg:
            raise Fail(
                f"ffmpeg not found: {gw}x{gh} must be scaled to {fw}x{fh}.\n"
                "Install ffmpeg (brew install ffmpeg), set FFMPEG_BIN, or pass --native to keep the model size.",
                4,
            )

    seed = a.seed if a.seed is not None else random.SystemRandom().randrange(1, 2**31)
    d = out_dir(a)
    name = part(a.name, "--name") if a.name else f"{slug(user_prompt)}-{seed}"
    final_path = os.path.join(d, f"{name}.png")
    native_path = final_path if native_only else os.path.join(d, f"{name}.native.png")
    side_path = os.path.join(d, f"{name}.json")
    for p in (final_path, native_path, side_path):
        if os.path.exists(p) and not a.overwrite:
            raise Fail(f"exists: {p} (pass --overwrite or --name)", 1)
    os.makedirs(d, exist_ok=True)

    # The engine writes into a fresh staging folder, so it never meets an existing file
    # (mflux renames its output then) and a failed run leaves nothing half done.
    stage = tempfile.mkdtemp(prefix="keyframes-")
    try:
        stage_native = os.path.join(stage, "native.png")
        cmd = [engine]
        if kind == "same-face":
            cmd += ["--model", key, "--image-paths", *refs]
        cmd += [f"--prompt={prompt}", "--width", str(gw), "--height", str(gh), "--seed", str(seed)]
        if a.steps:
            cmd += ["--steps", str(a.steps)]
        elif kind == "same-face":
            cmd += ["--steps", "4"]
        cmd += ["--output", stage_native]

        t0 = time.time()
        log(f"generating {gw}x{gh} with {key}, seed {seed}")
        run(cmd)
        if not os.path.isfile(stage_native):
            raise Fail("engine finished but wrote no image", 1)
        gen_s = time.time() - t0
        stage_final = stage_native
        if not native_only:
            stage_final = os.path.join(stage, "final.png")
            to_final(stage_native, stage_final, fw, fh, ffmpeg)
            if not os.path.isfile(stage_final):
                raise Fail("ffmpeg wrote no image", 1)
        shutil.move(stage_native, native_path)
        if not native_only:
            shutil.move(stage_final, final_path)
    finally:
        shutil.rmtree(stage, ignore_errors=True)

    m = MODELS[key]
    side = {
        "image": os.path.basename(final_path),
        "native_image": os.path.basename(native_path),
        "kind": kind,
        "prompt": prompt,
        "user_prompt": user_prompt,
        "style_file": os.path.abspath(os.path.expanduser(a.style_file)) if a.style_file else None,
        "seed": seed,
        "model": key,
        "weights_repo": m["repo"],
        "weight_license": m["license"],
        "commercial": m["commercial"],
        "noncommercial_ok_flag": bool(a.noncommercial_ok),
        "generated_size": [gw, gh],
        "final_size": [fw, fh] if not native_only else [gw, gh],
        "refs": [{"path": r, "sha256": sha256(r)} for r in refs],
        "engine": os.path.basename(engine),
        "seconds": round(gen_s, 1),
        "ai_generated": True,
        "created": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    with open(side_path, "w", encoding="utf-8") as f:
        json.dump(side, f, indent=2)
        f.write("\n")
    log(f"image={final_path}")
    log(f"sidecar={side_path}")
    log(f"seed={seed} seconds={side['seconds']}")
    return 0


SCORER = r"""
import json, sys
import face_recognition as fr
import numpy as np
args = sys.argv[1:]
i = args.index("--candidate")
refs, cand = args[:i], args[i + 1]
def enc(p):
    img = fr.load_image_file(p)
    boxes = fr.face_locations(img, number_of_times_to_upsample=1, model="hog")
    if not boxes:
        return None
    big = max(boxes, key=lambda b: (b[2] - b[0]) * (b[1] - b[3]))
    return fr.face_encodings(img, [big], num_jitters=3)[0]
R = [(p, enc(p)) for p in refs]
used = [(p, e) for p, e in R if e is not None]
out = {"refs_used": [p for p, _ in used], "refs_noface": [p for p, e in R if e is None]}
c = enc(cand)
if c is None or not used:
    out["noface"] = True
else:
    d = np.linalg.norm(np.array([e for _, e in used]) - c, axis=1)
    out["mean"] = float(d.mean())
    out["min"] = float(d.min())
print(json.dumps(out))
"""


def score(a):
    py = os.path.expanduser(os.environ.get("LIKENESS_PYTHON") or "python3")
    how = (
        "Likeness scoring needs a python with dlib and face_recognition. Set LIKENESS_PYTHON to it.\n"
        "To make one (this script never installs it):\n"
        "  uv venv ~/.venvs/likeness\n"
        "  uv pip install --python ~/.venvs/likeness/bin/python dlib-bin face_recognition_models 'setuptools<81' pillow numpy\n"
        "  uv pip install --python ~/.venvs/likeness/bin/python --no-deps face_recognition\n"
        "  export LIKENESS_PYTHON=~/.venvs/likeness/bin/python"
    )
    if not shutil.which(py) and not os.path.isfile(py):
        raise Fail(f"python not found: {py}\n{how}", 4)
    try:
        probe = subprocess.run([py, "-I", "-c", "import dlib, face_recognition, numpy; print('keyframes-likeness-ok')"], capture_output=True, text=True)
    except OSError as e:
        raise Fail(f"cannot run {py}: {e}\n{how}", 4)
    if probe.returncode != 0 or "keyframes-likeness-ok" not in probe.stdout:
        raise Fail(f"dlib is not importable in {py}\n{how}", 4)
    refs = [os.path.abspath(os.path.expanduser(r)) for r in a.ref]
    cand = os.path.abspath(os.path.expanduser(a.candidate))
    for p in refs + [cand]:
        if not os.path.isfile(p):
            raise Fail(f"image not found: {p}", 4)
    r = subprocess.run([py, "-I", "-c", SCORER, *refs, "--candidate", cand], capture_output=True, text=True)
    if r.returncode != 0:
        raise Fail("scoring failed\n" + "\n".join(r.stderr.strip().splitlines()[-8:]), 1)
    try:
        res = json.loads(r.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        raise Fail("scoring printed no JSON", 1)
    if res.get("noface"):
        log(f"{os.path.basename(cand)}\tnoface")
        raise Fail("no face found in the candidate or in any reference", 1)
    mean, mn = res["mean"], res["min"]
    verdict = "same person" if mean < 0.6 else "different person"
    log(f"{os.path.basename(cand)}\tmean {mean:.3f}\tmin {mn:.3f}\t{verdict}")
    log("distance: lower is closer, under 0.60 is the same-person line, 0.30 or less is a strong match. Check by eye as well.")
    return 0


def licenses(_a):
    for k, m in MODELS.items():
        log(f"{k}\t{m['repo']}\t{m['license']}\tcommercial={'yes' if m['commercial'] else 'no'}\t{m['kind']}\t{m['card']}")
    log("checked against the Hugging Face model cards on 2026-11-26")
    return 0


def common(p, with_ref):
    p.add_argument("--prompt")
    p.add_argument("--prompt-file")
    p.add_argument("--style-file", help="brand style file (markdown or text) appended to the prompt")
    p.add_argument("--size", default="reel", help="reel (1080x1920), square, portrait (1080x1350), landscape (1920x1080) or WIDTHxHEIGHT")
    p.add_argument("--native", action="store_true", help="keep the model's own size, no ffmpeg step")
    p.add_argument("--seed", type=int)
    p.add_argument("--steps", type=int)
    p.add_argument("--model")
    p.add_argument("--name")
    p.add_argument("--out-dir")
    p.add_argument("--owner")
    p.add_argument("--job", default="keyframes")
    p.add_argument("--overwrite", action="store_true")
    p.add_argument("--noncommercial-ok", action="store_true", help="allow a weight whose license bars commercial use")
    if with_ref:
        p.add_argument("--ref", nargs="+", required=True, help="reference photos of the person")
        p.add_argument("--no-prefix", action="store_true", help="do not add 'The same person as in the reference image.'")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="keyframes.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    common(sub.add_parser("still", help="styled still from a prompt"), False)
    common(sub.add_parser("same-face", help="same-face still from reference photos"), True)
    sp = sub.add_parser("score", help="likeness distance between references and a candidate (dlib)")
    sp.add_argument("--ref", nargs="+", required=True)
    sp.add_argument("--candidate", required=True)
    sub.add_parser("licenses", help="print the pinned weight licenses")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 0 if e.code == 0 else 2
    try:
        if a.cmd == "still":
            return generate(a, "still")
        if a.cmd == "same-face":
            return generate(a, "same-face")
        if a.cmd == "score":
            return score(a)
        return licenses(a)
    except Fail as e:
        print(f"keyframes: {e}", file=sys.stderr)
        return e.code


if __name__ == "__main__":
    sys.exit(main())
