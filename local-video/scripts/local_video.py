#!/usr/bin/env python3
"""Local video on this Mac: image to video and text to video, upscale, Ken Burns. Python 3 standard library only.

  local_video.py i2v     --image still.png --prompt "..." [--engine h3|ltx] [--seconds 5] --out-dir DIR
  local_video.py t2v     --prompt "..." [--seconds 5] [--aspect 9:16] --out-dir DIR
  local_video.py upscale --video clip.mp4 [--mult 2] --out-dir DIR
  local_video.py kenburns --image still.png --duration 4 --out-dir DIR
  local_video.py kenburns --shots shots.json --parts parts.json --out-dir DIR

Heavy commands (i2v, t2v, upscale) go through ComfyUI, one heavy model at a time (see comfy.py).
Exit codes: 0 ok, 1 error, 2 usage, 3 needs a human decision (licence not accepted, low memory), 4 not found (engine, ComfyUI, ffmpeg).
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import comfy  # noqa: E402

WORKFLOWS = os.path.join(os.path.dirname(HERE), "workflows")

LICENSES = {
    "minimax-h3": (
        "MiniMax H3 Community License. It does not cover use in the US, EU, UK or South Korea, it needs a separate "
        "authorisation above US$20M annual revenue, and commercial use of the outputs needs a MiniMax licence. "
        "Read the licence on the model card before any client or paid work. Pass --license-ok to say you did."),
    "ltx": "LTX-Video weights carry their own licence (an OpenRAIL-style licence, with revenue limits on some versions). Read the one for the checkpoint you use before commercial work.",
    "seedvr2": "SeedVR2 is Apache-2.0 (ByteDance-Seed). Check the weights' model card for the build you use.",
}

ASPECTS = {"9:16": "9:16 (Portrait Widescreen)", "16:9": "16:9 (Widescreen)", "1:1": "1:1 (Square)"}

MOVES = {  # zoom, x, y expressions for zoompan; F is the frame count, on the output frame number
    "push_in": ("1+0.16*on/F", "iw/2-iw/zoom/2", "ih/2-ih/zoom/2"),
    "pull_out": ("1.16-0.16*on/F", "iw/2-iw/zoom/2", "ih/2-ih/zoom/2"),
    "pan_left": ("1.15", "(iw-iw/zoom)*(1-on/F)", "ih/2-ih/zoom/2"),
    "pan_right": ("1.15", "(iw-iw/zoom)*on/F", "ih/2-ih/zoom/2"),
    "tilt_up": ("1.15", "iw/2-iw/zoom/2", "(ih-ih/zoom)*(1-on/F)"),
    "tilt_down": ("1.15", "iw/2-iw/zoom/2", "(ih-ih/zoom)*on/F"),
    "drift": ("1.08+0.06*on/F", "(iw-iw/zoom)*on/F*0.5", "ih/2-ih/zoom/2"),
}


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def stamp():
    return time.strftime("%Y%m%d-%H%M%S")


def write_sidecar(path, data):
    data = {"tool": "local-video", "created": time.strftime("%Y-%m-%dT%H:%M:%S%z"), **data}
    with open(path, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")


def add_heavy_args(ap):
    ap.add_argument("--out-dir", default="local-video-out", help="where the result and its .json sidecar go")
    ap.add_argument("--name", help="output file name without extension")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--url", help="ComfyUI base URL (default: COMFY_URL, else ports 8188, 8189, 8288)")
    ap.add_argument("--start", action="store_true", help="open Comfy Desktop if no ComfyUI answers (macOS)")
    ap.add_argument("--need-gb", type=float, help="free memory the run needs; below it the run is refused (exit 3). Template default otherwise")
    ap.add_argument("--timeout", type=float, default=3600, help="seconds to wait for the job")
    ap.add_argument("--lock-timeout", type=float, default=3600, help="seconds to wait for the heavy-model lock")
    ap.add_argument("--settle", type=float, default=3.0, help="seconds to let ComfyUI release memory after /free")
    ap.add_argument("--dry-run", action="store_true", help="print the plan as JSON and stop; nothing runs")
    ap.add_argument("--license-ok", action="store_true", help="you have read the model licence (required for H3)")


def build_parser():
    ap = argparse.ArgumentParser(prog="local_video.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    for mode in ("i2v", "t2v"):
        sp = sub.add_parser(mode)
        add_heavy_args(sp)
        sp.add_argument("--prompt", required=True)
        sp.add_argument("--engine", choices=("h3", "ltx"), default="h3")
        sp.add_argument("--seconds", type=float, default=5.0)
        sp.add_argument("--steps", type=int)
        sp.add_argument("--megapixels", type=float, default=0.2, help="H3 canvas size; 0.2 is 352x608 in portrait")
        if mode == "i2v":
            sp.add_argument("--image", required=True)
            sp.add_argument("--ltx-checkpoint", help="LTX checkpoint file name as ComfyUI lists it")
            sp.add_argument("--width", type=int, help="LTX only, multiple of 32")
            sp.add_argument("--height", type=int, help="LTX only, multiple of 32")
        else:
            sp.add_argument("--aspect", default="9:16", help="9:16, 16:9, 1:1 or a ResolutionSelector choice")

    sp = sub.add_parser("upscale")
    add_heavy_args(sp)
    sp.add_argument("--video", required=True)
    sp.add_argument("--mult", type=float, default=2.0)
    sp.add_argument("--chunk", type=int, help="frames per chunk (lower uses less memory)")

    sp = sub.add_parser("kenburns")
    sp.add_argument("--image", action="append", default=[], help="a still; repeat for several (each gets the same duration)")
    sp.add_argument("--shots", help="JSON list of {image, move, duration | line, share}")
    sp.add_argument("--duration", type=float, help="seconds per shot")
    sp.add_argument("--parts", help="voice parts JSON; a shot lasts as long as its line")
    sp.add_argument("--line", type=int, default=0, help="which part a single --image plays under")
    sp.add_argument("--move", choices=sorted(MOVES), default="push_in")
    sp.add_argument("--size", default="1080x1920")
    sp.add_argument("--fps", type=int, default=24)
    sp.add_argument("--out-dir", default="local-video-out")
    sp.add_argument("--name")
    sp.add_argument("--dry-run", action="store_true")
    return ap


# ---------------------------------------------------------------- heavy jobs

def heavy(a, template, params, sidecar, preferred_ext):
    meta, graph = comfy.load_template(os.path.join(WORKFLOWS, template))
    lic = meta.get("license")
    p = comfy.coerce(meta, {k: v for k, v in params.items() if v is not None})
    plan = {"template": template, "engine": meta.get("engine"), "params": {k: v for k, v in p.items()}, "need_gb": comfy.need_gb_for(meta, a.need_gb), "license": lic}
    if a.dry_run:
        print(json.dumps(plan, indent=1))
        return 0
    if lic in LICENSES:
        log("licence: " + LICENSES[lic])
    if lic == "minimax-h3" and not a.license_ok:
        raise comfy.NeedsDecision("MiniMax H3 needs --license-ok. Read the licence text above first; it restricts commercial use and some countries.")
    path = os.path.join(WORKFLOWS, template)

    def preflight(c):
        comfy.resolve_models(c, meta, p, comfy.fill(graph, {**p, "image": "x", "video": "x"}))

    t0 = time.time()
    with comfy.heavy_session(a.url, a.start, plan["need_gb"], a.lock_timeout, a.settle, preflight) as c:
        for key in ("image", "video"):
            if params.get(key):
                p[key] = c.upload(params[key])
        os.makedirs(a.out_dir, exist_ok=True)
        res = comfy.run_template(c, path, p, a.out_dir, a.timeout)
        base = c.base
    outs = [f for f in res["files"] if f["kind"] == "video"] or res["files"]
    main = outs[0]["path"]
    name = a.name or f"{a.cmd}-{meta.get('engine')}-{stamp()}"
    ext = os.path.splitext(main)[1] or preferred_ext
    final = os.path.join(a.out_dir, name + ext)
    if os.path.abspath(final) != os.path.abspath(main):
        os.replace(main, final)
    shown = {k: v for k, v in res["params"].items() if k not in ("image", "video")}
    write_sidecar(os.path.join(a.out_dir, name + ".json"), {
        "command": a.cmd, "engine": meta.get("engine"), "workflow": template, "params": shown, "input": params.get("image") or params.get("video"),
        "output": os.path.basename(final), "seconds_elapsed": round(time.time() - t0, 1), "comfy": base, "license": lic,
        "license_note": LICENSES.get(lic), "workflow_note": meta.get("note")})
    print(f"video={final}")
    print(f"sidecar={os.path.join(a.out_dir, name + '.json')}")
    print(f"seconds={round(time.time() - t0, 1)}")
    return 0


def cmd_gen(a):
    t2v = a.cmd == "t2v"
    if a.seconds <= 0 or a.seconds > 30:
        raise comfy.Usage("--seconds must be between 0 and 30")
    if not t2v and not os.path.isfile(a.image):
        raise comfy.Usage(f"no such image: {a.image}")
    seed = a.seed if a.seed is not None else None
    if a.engine == "h3":
        params = {"prompt": a.prompt, "seconds": a.seconds, "megapixels": a.megapixels, "steps": a.steps, "seed": seed}
        if t2v:
            params["aspect"] = ASPECTS.get(a.aspect, a.aspect)
        else:
            params["image"] = a.image
        return heavy(a, "h3_t2v.json" if t2v else "h3_i2v.json", params, {}, ".mp4")
    if t2v:
        raise comfy.Usage("LTX is wired for image to video only. Use i2v with --engine ltx, or t2v with the default engine h3.")
    fps = 24
    frames = int(round(a.seconds * fps / 8.0)) * 8 + 1
    params = {"prompt": a.prompt, "image": a.image, "frames": frames, "fps": fps, "steps": a.steps, "seed": seed,
              "width": a.width, "height": a.height, "ckpt": a.ltx_checkpoint}
    return heavy(a, "ltx_i2v.json", params, {}, ".mp4")


def cmd_upscale(a):
    if not os.path.isfile(a.video):
        raise comfy.Usage(f"no such video: {a.video}")
    if a.mult < 1 or a.mult > 4:
        raise comfy.Usage("--mult must be between 1 and 4")
    return heavy(a, "seedvr2_upscale.json", {"video": a.video, "mult": a.mult, "chunk": a.chunk, "seed": a.seed}, {}, ".mp4")


# ---------------------------------------------------------------- Ken Burns

def part_seconds(parts, line):
    items = parts.get("parts", parts) if isinstance(parts, dict) else parts
    if not isinstance(items, list) or not 0 <= line < len(items):
        raise comfy.Usage(f"parts file has no line {line}")
    it = items[line]
    if isinstance(it, (int, float)):
        return float(it)
    if isinstance(it, dict):
        for k in ("duration", "seconds", "dur", "length"):
            if isinstance(it.get(k), (int, float)):
                return float(it[k])
        if isinstance(it.get("start"), (int, float)) and isinstance(it.get("end"), (int, float)):
            return float(it["end"]) - float(it["start"])
    raise comfy.Usage(f"part {line} has no duration (expected a number, or duration, seconds, or start and end)")


def kenburns_plan(a):
    """A list of {image, move, seconds, name} from --shots, or from --image with --duration or --parts."""
    parts = None
    if a.parts:
        with open(a.parts) as f:
            parts = json.load(f)
    shots = []
    if a.shots:
        base = os.path.dirname(os.path.abspath(a.shots))
        with open(a.shots) as f:
            raw = json.load(f)
        for i, s in enumerate(raw):
            img = os.path.expanduser(s["image"])
            img = img if os.path.isabs(img) else os.path.join(base, img)
            if "duration" in s:
                secs = float(s["duration"])
            elif "line" in s and parts is not None:
                secs = part_seconds(parts, int(s["line"])) * float(s.get("share", 1.0))
            elif a.duration:
                secs = a.duration
            else:
                raise comfy.Usage(f"shot {i + 1} has no duration: give duration, or line with --parts, or --duration")
            shots.append({"image": img, "move": s.get("move", a.move), "seconds": secs})
    else:
        if not a.image:
            raise comfy.Usage("give --image (or --shots)")
        for i, img in enumerate(a.image):
            if a.duration:
                secs = a.duration
            elif parts is not None:
                secs = part_seconds(parts, a.line + i)
            else:
                raise comfy.Usage("give --duration, or --parts with --line")
            shots.append({"image": img, "move": a.move, "seconds": secs})
    for i, s in enumerate(shots):
        if not os.path.isfile(s["image"]):
            raise comfy.Usage(f"no such image: {s['image']}")
        if s["move"] not in MOVES:
            raise comfy.Usage(f"unknown move '{s['move']}'. Moves: {', '.join(sorted(MOVES))}")
        if not 0.2 <= s["seconds"] <= 120:
            raise comfy.Usage(f"shot {i + 1} lasts {s['seconds']}s; allowed 0.2 to 120")
    return shots


def kenburns_cmd(img, move, secs, size, fps, dst):
    w, h = size
    frames = max(2, int(round(secs * fps)))
    z, x, y = (re.sub(r"\bF\b", str(frames), e) for e in MOVES[move])
    big = f"{w * 2}:{h * 2}"
    vf = (f"scale={big}:force_original_aspect_ratio=increase,crop={big},"
          f"zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s={w}x{h}:fps={fps},format=yuv420p")
    return ["ffmpeg", "-v", "error", "-y", "-loop", "1", "-i", img, "-vf", vf, "-frames:v", str(frames),
            "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-movflags", "+faststart", "-an", dst], frames


def cmd_kenburns(a):
    m = re.fullmatch(r"(\d{2,5})x(\d{2,5})", a.size)
    if not m:
        raise comfy.Usage("--size looks like 1080x1920")
    size = (int(m.group(1)) // 2 * 2, int(m.group(2)) // 2 * 2)
    shots = kenburns_plan(a)
    plan = [{"image": s["image"], "move": s["move"], "seconds": round(s["seconds"], 3)} for s in shots]
    if a.dry_run:
        print(json.dumps({"size": a.size, "fps": a.fps, "shots": plan}, indent=1))
        return 0
    if not shutil.which("ffmpeg"):
        raise comfy.Missing("ffmpeg is not installed (brew install ffmpeg)")
    os.makedirs(a.out_dir, exist_ok=True)
    base = a.name or f"kenburns-{stamp()}"
    outs = []
    for i, s in enumerate(shots):
        name = base if len(shots) == 1 else f"{base}-{i + 1:02d}"
        dst = os.path.join(a.out_dir, name + ".mp4")
        cmd, frames = kenburns_cmd(s["image"], s["move"], s["seconds"], size, a.fps, dst)
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            raise comfy.ComfyError("ffmpeg failed: " + r.stderr.strip()[-600:])
        write_sidecar(os.path.join(a.out_dir, name + ".json"), {
            "command": "kenburns", "engine": "ffmpeg-zoompan", "input": os.path.basename(s["image"]), "move": s["move"],
            "seconds": round(frames / a.fps, 3), "frames": frames, "fps": a.fps, "size": a.size, "output": os.path.basename(dst)})
        print(f"video={dst}")
        outs.append(dst)
    return 0


def main(argv):
    a = build_parser().parse_args(argv)
    try:
        if a.cmd in ("i2v", "t2v"):
            return cmd_gen(a)
        if a.cmd == "upscale":
            return cmd_upscale(a)
        return cmd_kenburns(a)
    except comfy.ComfyError as e:
        log(f"error: {e}")
        return e.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
