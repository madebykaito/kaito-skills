#!/bin/sh
. "$(dirname "$0")/lib.sh"
test_fake_api() {
  mk_home
  command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null || { echo 'skip: ffmpeg missing'; return; }
  ffmpeg -v error -f lavfi -i color=s=1080x1920:r=25:d=3 -f lavfi -i sine=sample_rate=48000:duration=3 -c:v libx264 -profile:v high -pix_fmt yuv420p -c:a aac -ac 2 -ar 48000 -movflags +faststart -shortest "$HOME/source.mp4"
  cat > "$HOME/server.py" <<'PY'
import http.server,json,os
class H(http.server.BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def do_POST(self):
  data=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
  assert data['video_script']=='Fixture narration' and data['video_source']=='local'
  self.reply(json.dumps({'data':{'task_id':'abc'}}).encode())
 def do_GET(self):
  if self.path.startswith('/api/v1/tasks/'): self.reply(json.dumps({'data':{'state':1,'videos':['/tasks/abc/final.mp4']}}).encode())
  else: self.reply(open(os.path.join(os.environ['HOME'],'source.mp4'),'rb').read())
 def reply(self,data):
  self.send_response(200); self.send_header('Content-Length',str(len(data))); self.end_headers(); self.wfile.write(data)
s=http.server.HTTPServer(('127.0.0.1',0),H)
open(os.path.join(os.environ['HOME'],'port'),'w').write(str(s.server_port))
s.serve_forever()
PY
  python3 "$HOME/server.py" & pid=$!
  trap 'kill "$pid" 2>/dev/null || :' EXIT
  n=0; while [ ! -f "$HOME/port" ] && [ "$n" -lt 50 ]; do sleep .1; n=$((n+1)); done
  python3 "$REPO/shortform-video/scripts/shortform-video.py" --topic fixture --script 'Fixture narration' --material "$HOME/source.mp4" --audio "$HOME/source.mp4" --api "http://127.0.0.1:$(cat "$HOME/port")" --out "$HOME/out.mp4" || return 1
  assert_file "$HOME/out.mp4"
}
