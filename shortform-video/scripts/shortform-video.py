#!/usr/bin/env python3
"""Create a short with a local MoneyPrinterTurbo API, then run preflight."""
import argparse, json, pathlib, subprocess, sys, tempfile, time, urllib.parse, urllib.request

def request(url, data=None):
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None, headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(req, timeout=30) as r: return json.load(r)

def main():
    p=argparse.ArgumentParser(); p.add_argument('--topic',required=True); p.add_argument('--script',help='Host-written narration'); p.add_argument('--ollama-model'); p.add_argument('--api',default='http://127.0.0.1:8080'); p.add_argument('--material',action='append',required=True); p.add_argument('--owner'); p.add_argument('--voice',default='en-US-AriaNeural'); p.add_argument('--audio',help='Local narration audio in place of TTS'); p.add_argument('--target',choices=['ig-reels','yt-shorts','linkedin'],default='ig-reels'); p.add_argument('--out',required=True); p.add_argument('--timeout',type=int,default=1800); a=p.parse_args()
    try:
        u=urllib.parse.urlsplit(a.api)
        if u.scheme != 'http' or u.hostname not in ('localhost','127.0.0.1','::1') or u.username or u.password: raise ValueError('MoneyPrinterTurbo API must be local HTTP')
        if not a.audio:
            if not a.owner: raise ValueError('Edge TTS needs --owner and prior cloud consent; or use --audio')
            engines=pathlib.Path(__file__).resolve().parents[2]/'business/scripts/kaito-engines.mjs'
            consent=subprocess.run(['node',str(engines),'consent','edge-tts','--owner',a.owner,'--status'],capture_output=True,text=True)
            if consent.returncode or not consent.stdout.strip().endswith(': granted'): raise ValueError('Edge TTS consent is not granted for this owner')
        script=a.script
        if not script and a.ollama_model:
            script=request('http://127.0.0.1:11434/api/generate',{'model':a.ollama_model,'prompt':'Write concise spoken narration for a short video about: '+a.topic,'stream':False})['response']
        if not script or not script.strip(): raise ValueError('provide --script or --ollama-model')
        materials=[{'provider':'local','url':str(pathlib.Path(x).resolve())} for x in a.material]
        body={'video_subject':a.topic,'video_script':script,'video_aspect':'9:16','video_source':'local','video_materials':materials,'voice_name':a.voice,'video_count':1}
        if a.audio: body.update({'custom_audio_file':str(pathlib.Path(a.audio).resolve()), 'subtitle_enabled':False})
        base=a.api.rstrip('/'); task=request(base+'/api/v1/videos',body)['data']['task_id']; deadline=time.monotonic()+a.timeout
        while True:
            state=request(base+'/api/v1/tasks/'+urllib.parse.quote(task,safe=''))['data']
            if state['state']==1: break
            if state['state']==-1: raise ValueError('MoneyPrinterTurbo task failed: '+str(state.get('error','unknown error')))
            if time.monotonic()>=deadline: raise ValueError('MoneyPrinterTurbo task timed out')
            time.sleep(2)
        url=urllib.parse.urljoin(base+'/',state['videos'][0]); result=urllib.parse.urlsplit(url)
        if (result.scheme,result.hostname,result.port)!=(u.scheme,u.hostname,u.port): raise ValueError('output URL is not on the local API')
        with tempfile.TemporaryDirectory() as tmp:
            source = pathlib.Path(tmp) / 'source.mp4'
            with urllib.request.urlopen(url,timeout=60) as r, source.open('wb') as out:
                while True:
                    chunk=r.read(1024*1024)
                    if not chunk: break
                    out.write(chunk)
            subprocess.run(['ffmpeg','-v','error','-y','-i',str(source),'-vf','scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1','-c:v','libx264','-profile:v','high','-pix_fmt','yuv420p','-c:a','aac','-b:a','128k','-ar','48000','-ac','2','-movflags','+faststart',a.out],check=True)
        preflight=pathlib.Path(__file__).resolve().parents[2]/'reel-assemble/scripts/media-spec.py'
        return subprocess.call([sys.executable,str(preflight),'check',a.out,'--target',a.target])
    except (OSError,ValueError,KeyError,IndexError,subprocess.CalledProcessError) as e:
        print(f'error: {e}',file=sys.stderr); return 1
if __name__=='__main__': sys.exit(main())
