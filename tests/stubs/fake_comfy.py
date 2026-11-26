#!/usr/bin/env python3
"""A fake ComfyUI for tests. Python 3 standard library only.

Serves /system_stats, /queue, /free, /prompt, /history/<id>, /view, /object_info/<node> and /upload/image.
Every request is appended to --log as one JSON line; /prompt lines carry the submitted workflow.

  fake_comfy.py --port-file F --log L [--ram-free-gb 30] [--ram-total-gb 48] [--have-from t1.json,t2.json]
                [--have FILE] [--missing-node NAME] [--busy] [--audio-rate 48000] [--fail-job]
"""
import argparse
import io
import json
import os
import re
import sys
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

GB = 1024 ** 3
ap = argparse.ArgumentParser()
ap.add_argument("--port-file", required=True)
ap.add_argument("--log", required=True)
ap.add_argument("--ram-free-gb", type=float, default=30)
ap.add_argument("--ram-total-gb", type=float, default=48)
ap.add_argument("--have-from", default="")
ap.add_argument("--have", action="append", default=[])
ap.add_argument("--missing-node", action="append", default=[])
ap.add_argument("--busy", action="store_true")
ap.add_argument("--audio-rate", type=int, default=48000)
ap.add_argument("--fail-job", action="store_true")
A = ap.parse_args()

HAVE = set(A.have)
for t in filter(None, A.have_from.split(",")):
    for m in json.load(open(t)).get("meta", {}).get("models", []):
        if "{{" not in m["file"]:
            HAVE.add(m["file"])
JOBS = {}


def wav_bytes(rate):
    b = io.BytesIO()
    with wave.open(b, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x00\x00\x00\x00" * rate)  # one second of silence
    return b.getvalue()


def note(entry):
    with open(A.log, "a") as f:
        f.write(json.dumps(entry) + "\n")


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        u = urlparse(self.path)
        note({"m": "GET", "p": u.path})
        if u.path == "/system_stats":
            total, free = int(A.ram_total_gb * GB), int(A.ram_free_gb * GB)
            return self.send(200, {"system": {"ram_total": total, "ram_free": free}, "devices": [{"type": "mps", "vram_total": total, "vram_free": free}]})
        if u.path == "/queue":
            return self.send(200, {"queue_running": [["x"]] if A.busy else [], "queue_pending": []})
        m = re.fullmatch(r"/history/(\w+)", u.path)
        if m:
            job = JOBS.get(m.group(1))
            return self.send(200, {m.group(1): job} if job else {})
        m = re.fullmatch(r"/object_info/(.+)", u.path)
        if m:
            node = m.group(1)
            if node in A.missing_node:
                return self.send(200, {})
            have = sorted(HAVE)
            fields = {k: [have] for k in ("unet_name", "clip_name", "vae_name", "lora_name", "ckpt_name")}
            return self.send(200, {node: {"input": {"required": fields}}})
        if u.path == "/view":
            fn = parse_qs(u.query)["filename"][0]
            if fn.endswith(".wav"):
                return self.send(200, wav_bytes(A.audio_rate), "audio/wav")
            return self.send(200, b"fake-mp4-bytes:" + fn.encode(), "video/mp4")
        self.send(404, {"error": "not found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n)
        p = urlparse(self.path).path
        if p == "/free":
            note({"m": "POST", "p": p, "body": json.loads(raw or b"{}")})
            return self.send(200, {})
        if p == "/upload/image":
            fn = re.search(rb'filename="([^"]+)"', raw)
            name = fn.group(1).decode() if fn else "upload.bin"
            note({"m": "POST", "p": p, "name": name, "bytes": len(raw)})
            return self.send(200, {"name": name, "subfolder": "", "type": "input"})
        if p == "/prompt":
            body = json.loads(raw)
            graph = body["prompt"]
            note({"m": "POST", "p": p, "prompt": graph})
            if "{{" in json.dumps(graph):
                return self.send(400, {"error": {"message": "unfilled placeholder"}, "node_errors": {}})
            pid = "job%d" % (len(JOBS) + 1)
            outputs = {}
            for nid, node in graph.items():
                prefix = os.path.basename(str(node.get("inputs", {}).get("filename_prefix", "out")))
                if node["class_type"] == "SaveAudio":
                    outputs[nid] = {"audio": [{"filename": f"{prefix}_00001_.wav", "subfolder": "audio", "type": "output"}]}
                elif node["class_type"] == "SaveVideo":
                    outputs[nid] = {"images": [{"filename": f"{prefix}_00001_.mp4", "subfolder": "video", "type": "output"}], "animated": [True]}
            if A.fail_job:
                status = {"status_str": "error", "completed": False, "messages": [["execution_error", {"node_id": "1", "node_type": "Fake", "exception_message": "boom"}]]}
            else:
                status = {"status_str": "success", "completed": True, "messages": []}
            JOBS[pid] = {"status": status, "outputs": outputs}
            return self.send(200, {"prompt_id": pid, "number": 1, "node_errors": {}})
        self.send(404, {"error": "not found"})


srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
open(A.port_file + ".tmp", "w").write(str(srv.server_address[1]))
os.rename(A.port_file + ".tmp", A.port_file)
try:
    srv.serve_forever()
except KeyboardInterrupt:
    pass
