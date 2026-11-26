#!/usr/bin/env python3
"""Shared ComfyUI client for local-video and music. Python 3 standard library only.

What it does:
  - finds a running ComfyUI (COMFY_URL, else ports 8188, 8189, 8288) by probing /system_stats
  - takes the one-heavy-model lock (mkdir /tmp/kaito-heavy.lock, or KAITO_HEAVY_LOCK)
  - POSTs /free before a model loads and after the run
  - refuses to start when free memory is below what the workflow needs (exit 3, no swap)
  - fills a workflow template ({{name}} placeholders), submits it, polls /history, downloads outputs

Exit codes follow the repo contract: 0 ok, 1 error, 2 usage, 3 needs a human decision, 4 not found.

CLI:
  comfy.py probe [--url U] [--start]
  comfy.py free [--url U]
  comfy.py run <template.json> --out-dir DIR [--param k=v ...] [--need-gb N] [--start] [--url U]
"""
import argparse
import contextlib
import json
import mimetypes
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

PORTS = (8188, 8189, 8288)
LOCK_PATH = "/tmp/kaito-heavy.lock"
GB = 1024 ** 3
# Devices with their own memory pool. Apple silicon (mps) and cpu share system RAM.
SEPARATE_VRAM = ("cuda", "xpu", "hip", "rocm", "npu", "mlu")


class ComfyError(Exception):
    code = 1


class NeedsDecision(ComfyError):
    code = 3


class Missing(ComfyError):
    code = 4


class Usage(ComfyError):
    code = 2


def log(msg):
    print(msg, file=sys.stderr, flush=True)


# ---------------------------------------------------------------- http

def _open(req, timeout):
    return urllib.request.urlopen(req, timeout=timeout)


class Comfy:
    def __init__(self, base):
        self.base = base.rstrip("/")

    def get(self, path, timeout=30):
        with _open(self.base + path, timeout) as r:
            return json.loads(r.read().decode("utf-8", "replace") or "null")

    def post(self, path, data, timeout=60):
        req = urllib.request.Request(self.base + path, data=json.dumps(data).encode(),
                                     headers={"Content-Type": "application/json"})
        with _open(req, timeout) as r:
            body = r.read().decode("utf-8", "replace")
        return json.loads(body) if body.strip() else {}

    # ------------------------------------------------------------ memory

    def memory(self):
        """Free memory in GB for the pool a model would load into."""
        s = self.get("/system_stats")
        sysinfo = s.get("system") or {}
        dev = (s.get("devices") or [{}])[0]
        dtype = str(dev.get("type") or "").lower()
        ram_total, ram_free = sysinfo.get("ram_total"), sysinfo.get("ram_free")
        if dtype in SEPARATE_VRAM and dev.get("vram_total"):
            total, free, pool = dev["vram_total"], dev.get("vram_free", 0), "vram"
        else:
            total, free, pool = ram_total, ram_free, "ram"
            if total is None:  # server did not report system RAM: fall back to the device pool
                total, free = dev.get("vram_total", 0), dev.get("vram_free", 0)
        return {"pool": pool, "device": dtype or "unknown", "total_gb": (total or 0) / GB, "free_gb": (free or 0) / GB}

    def free(self, settle=3.0):
        """Unload models and release memory. ComfyUI applies this between jobs, so give it a moment."""
        try:
            self.post("/free", {"unload_models": True, "free_memory": True}, timeout=30)
        except (urllib.error.URLError, OSError, ValueError) as e:
            log(f"warn: /free failed: {e}")
            return False
        if settle:
            time.sleep(settle)
        return True

    def busy(self):
        """True when ComfyUI is running or has queued work. An unreadable queue counts as busy: better to stop than to load a second model."""
        try:
            q = self.get("/queue", timeout=10) or {}
        except (urllib.error.URLError, OSError, ValueError):
            return True
        return bool(q.get("queue_running") or q.get("queue_pending"))

    # ------------------------------------------------------------ models

    def options(self, node, field):
        """File choices a loader node offers, or None when the node is not installed."""
        try:
            info = self.get("/object_info/" + urllib.parse.quote(node), timeout=30)
        except urllib.error.HTTPError:
            return None
        spec = ((info or {}).get(node) or {}).get("input", {})
        entry = (spec.get("required") or {}).get(field) or (spec.get("optional") or {}).get(field)
        if not entry:
            return None
        first = entry[0]
        if isinstance(first, list):
            return [str(x) for x in first]
        if first == "COMBO" and len(entry) > 1 and isinstance(entry[1], dict):  # newer ComfyUI
            return [str(x) for x in entry[1].get("options", [])]
        return []

    # ------------------------------------------------------------ files

    def upload(self, path):
        """Put a local file in ComfyUI's input folder. Returns the name LoadImage and LoadVideo expect."""
        path = os.path.abspath(path)
        if not os.path.isfile(path):
            raise Usage(f"not a file: {path}")
        b = uuid.uuid4().hex
        name = os.path.basename(path)
        head = (f'--{b}\r\nContent-Disposition: form-data; name="image"; filename="{name}"\r\n'
                f"Content-Type: {mimetypes.guess_type(name)[0] or 'application/octet-stream'}\r\n\r\n").encode()
        tail = (f'\r\n--{b}--\r\n').encode()
        with open(path, "rb") as f:
            body = head + f.read() + tail
        req = urllib.request.Request(self.base + "/upload/image", data=body,
                                     headers={"Content-Type": f"multipart/form-data; boundary={b}"})
        with _open(req, 600) as r:
            res = json.loads(r.read().decode())
        sub = res.get("subfolder") or ""
        return f"{sub}/{res['name']}" if sub else res["name"]

    def download(self, entry, out_dir):
        """Save every output file of a finished job. Returns [{path, kind, node}]."""
        os.makedirs(out_dir, exist_ok=True)
        saved = []
        for node_id, out in (entry.get("outputs") or {}).items():
            for key in ("images", "gifs", "videos", "audio"):
                for f in out.get(key, []) or []:
                    if f.get("type") != "output":
                        continue
                    base = os.path.basename(str(f.get("filename", "")))  # the server names the file; never trust a path
                    if not base:
                        continue
                    dest, n = os.path.join(out_dir, base), 1
                    stem, ext = os.path.splitext(base)
                    while os.path.exists(dest):  # never overwrite a file already there; the suffix is made here, not by the server
                        n += 1
                        dest = os.path.join(out_dir, f"{stem}-{n}{ext}")
                    q = urllib.parse.urlencode({"filename": f["filename"], "subfolder": f.get("subfolder", ""), "type": "output"})
                    with _open(f"{self.base}/view?{q}", 600) as r, open(dest, "xb") as w:
                        shutil.copyfileobj(r, w)
                    saved.append({"path": dest, "kind": "audio" if key == "audio" else "video" if base.lower().endswith((".mp4", ".webm", ".mov", ".mkv", ".gif")) else "image", "node": node_id})
        return saved

    # ------------------------------------------------------------ jobs

    def submit(self, graph):
        try:
            res = self.post("/prompt", {"prompt": graph, "client_id": uuid.uuid4().hex})
        except urllib.error.HTTPError as e:
            raise ComfyError("ComfyUI rejected the workflow: " + _error_text(e.read().decode("utf-8", "replace")))
        return res["prompt_id"]

    def wait(self, pid, timeout=3600, poll=3.0, tick=30.0):
        t0 = last = time.time()
        fails = 0
        while True:
            try:
                h = self.get(f"/history/{pid}", timeout=30)
                fails = 0
            except (urllib.error.URLError, OSError, ValueError) as e:
                fails += 1
                if fails >= 5:
                    raise ComfyError(f"ComfyUI stopped answering while the job ran: {e}")
                h = {}
            if pid in (h or {}):
                entry = h[pid]
                st = entry.get("status") or {}
                if st.get("status_str") == "error":
                    raise ComfyError("ComfyUI failed the job: " + _exec_error(st))
                if st.get("completed") or st.get("status_str") == "success":
                    return entry
            now = time.time()
            if now - t0 > timeout:
                raise ComfyError(f"timed out after {timeout:.0f}s waiting for job {pid}")
            if now - last >= tick:
                log(f"  running, {now - t0:.0f}s")
                last = now
            time.sleep(poll)


def _error_text(body):
    try:
        j = json.loads(body)
    except ValueError:
        return body[:1500]
    parts = []
    err = j.get("error")
    if isinstance(err, dict):
        parts.append(str(err.get("message") or err.get("type") or ""))
        if err.get("details"):
            parts.append(str(err["details"]))
    for nid, ne in (j.get("node_errors") or {}).items():
        for e in ne.get("errors", []):
            parts.append(f"node {nid} ({ne.get('class_type')}): {e.get('message')} {e.get('details', '')}".strip())
    return "; ".join(p for p in parts if p)[:1500] or body[:1500]


def _exec_error(status):
    for m in status.get("messages", []):
        if m[0] == "execution_error":
            d = m[1]
            return f"{d.get('node_type')} node {d.get('node_id')}: {d.get('exception_message', '').strip()}"[:1500]
    return "unknown error"


# ---------------------------------------------------------------- finding the server

def _probe(base, timeout=2.0):
    try:
        with _open(base + "/system_stats", timeout) as r:
            j = json.loads(r.read().decode("utf-8", "replace"))
    except (urllib.error.URLError, OSError, ValueError):
        return False
    return isinstance(j, dict) and ("system" in j or "devices" in j)


def find_server(url=None, ports=PORTS):
    """The base URL of a running ComfyUI, or None. COMFY_URL (or url) wins; else probe the usual ports."""
    url = url or os.environ.get("COMFY_URL")
    if url:
        url = url.rstrip("/")
        return url if _probe(url) else None
    for p in ports:
        base = f"http://127.0.0.1:{p}"
        if _probe(base):
            return base
    return None


def ensure_server(url=None, start=False, wait=300):
    base = find_server(url)
    if base:
        return base
    if url or os.environ.get("COMFY_URL"):
        raise Missing(f"no ComfyUI answers at {url or os.environ['COMFY_URL']}")
    if not start:
        raise Missing("no ComfyUI answers on ports 8188, 8189 or 8288. Open Comfy Desktop, or pass --start to open it, or set COMFY_URL.")
    if sys.platform != "darwin":
        raise Missing("--start only knows Comfy Desktop on macOS. Start ComfyUI yourself or set COMFY_URL.")
    log('starting Comfy Desktop: open -a "Comfy Desktop"')
    if subprocess.run(["open", "-a", "Comfy Desktop"], capture_output=True).returncode != 0:
        raise Missing("could not open Comfy Desktop (is it installed?)")
    t0 = time.time()
    while time.time() - t0 < wait:
        base = find_server()
        if base:
            log(f"ComfyUI is up at {base} after {time.time() - t0:.0f}s")
            return base
        time.sleep(3)
    raise Missing(f"Comfy Desktop did not answer on ports 8188, 8189 or 8288 within {wait}s")


# ---------------------------------------------------------------- the heavy-model lock

def _pid_alive(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


@contextlib.contextmanager
def heavy_lock(timeout=3600, poll=None):
    """One heavy model at a time across every agent on this Mac. A mkdir lock, as the build contract says."""
    path = os.environ.get("KAITO_HEAVY_LOCK", LOCK_PATH)
    poll = float(os.environ.get("KAITO_LOCK_POLL", 15)) if poll is None else poll
    t0 = time.time()
    told = False
    while True:
        try:
            os.mkdir(path)
            break
        except FileExistsError:
            _steal_if_dead(path)
        if time.time() - t0 > timeout:
            raise NeedsDecision(f"another heavy model run holds {path} and did not finish within {timeout:.0f}s. Try later, or check that nothing is stuck.")
        if not told:
            log(f"waiting for the heavy-model lock ({path})")
            told = True
        time.sleep(poll)
    pidfile = os.path.join(path, "pid")
    try:
        with open(pidfile, "w") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass
    old = {}
    if hasattr(signal, "SIGTERM"):
        try:
            old[signal.SIGTERM] = signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
        except ValueError:  # not the main thread
            pass
    try:
        yield path
    finally:
        for sig, h in old.items():
            signal.signal(sig, h)
        for f in (pidfile,):
            try:
                os.remove(f)
            except OSError:
                pass
        try:
            os.rmdir(path)
        except OSError:
            pass


def _steal_if_dead(path):
    """A lock this tool took whose process is gone (kill -9, power loss) is cleared. Other agents' locks have no pid file and are never touched."""
    pidfile = os.path.join(path, "pid")
    try:
        pid = int(open(pidfile).read().strip())
        age = time.time() - os.path.getmtime(pidfile)
    except (OSError, ValueError):
        return
    if age > 60 and not _pid_alive(pid):
        log(f"clearing a stale lock left by process {pid}")
        try:
            os.remove(pidfile)
            os.rmdir(path)
        except OSError:
            pass


@contextlib.contextmanager
def heavy_session(url=None, start=False, need_gb=0.0, lock_timeout=3600, settle=3.0, preflight=None):
    """Lock, find ComfyUI, check the engine is installed, free whatever is loaded, check memory, yield a client, free again at the end."""
    with heavy_lock(lock_timeout):
        base = ensure_server(url, start)
        c = Comfy(base)
        if c.busy():
            raise NeedsDecision("ComfyUI is running another job. Wait for it to finish; two heavy models at once would swap.")
        if preflight:
            preflight(c)
        try:
            if not c.free(settle):
                raise ComfyError("could not POST /free to ComfyUI, so loaded models cannot be released. Not starting.")
            check_memory(c, need_gb)
            yield c
        finally:
            c.free(0)


def check_memory(c, need_gb):
    if not need_gb or need_gb <= 0:
        return
    m = c.memory()
    if m["free_gb"] < need_gb:
        raise NeedsDecision(
            f"not enough free memory: {m['free_gb']:.1f} GB free of {m['total_gb']:.1f} GB ({m['pool']}, {m['device']}), "
            f"this workflow needs {need_gb:.1f} GB. Not starting, so the Mac does not swap. "
            "Close other apps and retry, or lower the need with --need-gb if you know better.")
    log(f"memory ok: {m['free_gb']:.1f} GB free, {need_gb:.1f} GB needed ({m['pool']})")


# ---------------------------------------------------------------- templates

_PLACEHOLDER = re.compile(r"\{\{(\w+)\}\}")


def load_template(path):
    with open(path) as f:
        t = json.load(f)
    if not isinstance(t, dict) or "graph" not in t:
        raise Usage(f"{path} is not a workflow template (needs 'meta' and 'graph')")
    return t.get("meta", {}), t["graph"]


def fill(node, params):
    """Replace {{name}} in a workflow. A value that is only a placeholder keeps the parameter's type."""
    if isinstance(node, dict):
        return {k: fill(v, params) for k, v in node.items()}
    if isinstance(node, list):
        return [fill(v, params) for v in node]
    if isinstance(node, str) and "{{" in node:
        m = _PLACEHOLDER.fullmatch(node)
        if m:
            return _need(params, m.group(1))
        return _PLACEHOLDER.sub(lambda mm: str(_need(params, mm.group(1))), node)
    return node


def _need(params, name):
    if name not in params or params[name] is None:
        raise Usage(f"workflow needs a value for '{name}'")
    return params[name]


def coerce(meta, overrides):
    """Merge CLI strings over the template defaults, converting to each default's type."""
    out = dict(meta.get("defaults", {}))
    for k, v in overrides.items():
        d = out.get(k)
        if isinstance(v, str) and d is not None and not isinstance(d, str):
            try:
                v = type(d)(v) if not isinstance(d, bool) else v.lower() in ("1", "true", "yes")
            except ValueError:
                raise Usage(f"--param {k}: expected {type(d).__name__}, got '{v}'")
        out[k] = v
    return out


def resolve_models(c, meta, params, graph=None):
    """Check each model file the template names is known to ComfyUI. Returns {plain name: name ComfyUI lists}."""
    seen = {}
    for m in meta.get("models", []):
        want = fill(m["file"], params)
        opts = c.options(m["node"], m["input"])
        if opts is None:
            raise Missing(f"ComfyUI has no {m['node']} node. Install the node pack this engine needs (see the skill's SKILL.md).")
        hit = want if want in opts else next((o for o in opts if o.replace("\\", "/").endswith("/" + want)), None)
        if hit is None:
            raise Missing(f"missing engine: model file '{want}' is not in ComfyUI ({m['node']}.{m['input']}). Download it into the ComfyUI model folder; SKILL.md lists where it goes.")
        seen[want] = hit
    for ct in sorted({n.get("class_type") for n in (graph or {}).values() if isinstance(n, dict)}):
        try:
            info = c.get("/object_info/" + urllib.parse.quote(str(ct)), timeout=30)
        except urllib.error.HTTPError:
            info = None
        if not info or ct not in info:
            raise Missing(f"ComfyUI has no {ct} node. Install the node pack this engine needs (see the skill's SKILL.md).")
    return seen


def rename_models(graph, mapping):
    def walk(n):
        if isinstance(n, dict):
            return {k: walk(v) for k, v in n.items()}
        if isinstance(n, list):
            return [walk(v) for v in n]
        return mapping.get(n, n) if isinstance(n, str) else n
    return walk(graph)


def run_template(c, template, params, out_dir, timeout=3600):
    """Fill, check the models, submit, wait, download. The caller already holds the lock and has checked memory."""
    meta, graph = load_template(template)
    p = coerce(meta, params)
    mapping = resolve_models(c, meta, p, graph)
    graph = rename_models(fill(graph, p), mapping)
    t0 = time.time()
    pid = c.submit(graph)
    log(f"submitted {meta.get('name', os.path.basename(template))} as {pid}")
    entry = c.wait(pid, timeout=timeout)
    files = c.download(entry, out_dir)
    if not files:
        raise ComfyError("the job finished but produced no output files")
    return {"prompt_id": pid, "seconds": round(time.time() - t0, 1), "files": files, "params": p, "template": meta.get("name")}


def need_gb_for(meta, override=None):
    if override is not None:
        return float(override)
    env = os.environ.get("COMFY_NEED_GB")
    return float(env) if env else float(meta.get("need_gb", 0))


# ---------------------------------------------------------------- CLI

def _cli(argv):
    ap = argparse.ArgumentParser(prog="comfy.py", description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("probe", "free", "run"):
        sp = sub.add_parser(name)
        sp.add_argument("--url")
        sp.add_argument("--start", action="store_true", help="open Comfy Desktop if no ComfyUI answers (macOS)")
        if name == "run":
            sp.add_argument("template")
            sp.add_argument("--out-dir", required=True)
            sp.add_argument("--param", action="append", default=[], metavar="K=V")
            sp.add_argument("--need-gb", type=float)
            sp.add_argument("--timeout", type=float, default=3600)
            sp.add_argument("--license-ok", action="store_true", help="you have read the model licence (required for MiniMax H3)")
    a = ap.parse_args(argv)
    try:
        if a.cmd == "probe":
            base = ensure_server(a.url, a.start)
            c = Comfy(base)
            print(json.dumps({"url": base, **c.memory()}))
        elif a.cmd == "free":
            base = ensure_server(a.url, False)
            ok = Comfy(base).free(0)
            print("freed" if ok else "free failed")
            return 0 if ok else 1
        else:
            meta, _ = load_template(a.template)
            over = {}
            for kv in a.param:
                if "=" not in kv:
                    raise Usage(f"--param needs K=V, got '{kv}'")
                k, v = kv.split("=", 1)
                over[k] = v
            if meta.get("license") == "minimax-h3" and not a.license_ok:
                raise NeedsDecision("MiniMax H3 is under the MiniMax H3 Community License (restricts commercial use and some countries). Read it, then pass --license-ok.")
            with heavy_session(a.url, a.start, need_gb_for(meta, a.need_gb)) as c:
                res = run_template(c, a.template, over, a.out_dir, a.timeout)
            for f in res["files"]:
                print(f"{f['kind']}={f['path']}")
            print(f"seconds={res['seconds']}")
    except ComfyError as e:
        log(f"error: {e}")
        return e.code
    return 0


if __name__ == "__main__":
    sys.exit(_cli(sys.argv[1:]))
