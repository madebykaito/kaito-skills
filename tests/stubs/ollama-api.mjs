// Fake Ollama HTTP server. node ollama-api.mjs <port-file>
//   GET  /api/tags       a fixed list of pulled models (STUB_EMPTY=1: none)
//   POST /api/generate   {model, prompt, stream:false} -> {response}. The reply is "<model>|<prompt>", after a delay:
//                        a prompt containing "slow" takes 300 ms, any other 60 ms. An unknown model is a 404, as in Ollama.
//   GET  /_stats         {max, calls}: the most requests in flight at once, and the number of generate calls
import { createServer } from 'node:http';
import { writeFileSync } from 'node:fs';

const models = process.env.STUB_EMPTY ? [] : [
  ['llama3.2:1b', 'llama', '1.2B', '2026-11-01T10:00:00Z'],
  ['smollm2:360m', 'llama', '361.82M', '2026-11-02T10:00:00Z'],
  ['gemma3:12b', 'gemma3', '12.2B', '2026-11-03T10:00:00Z'],
  ['qwen3:8b', 'qwen3', '8.2B', '2026-11-04T10:00:00Z'],
  ['llama3.3:70b', 'llama', '70.6B', '2026-11-05T10:00:00Z'],
  ['nomic-embed-text:latest', 'nomic-bert', '137M', '2026-11-06T10:00:00Z'],
  ['gpt-oss:120b-cloud', 'gptoss', '116.8B', '2026-11-07T10:00:00Z'],
].map(([name, family, parameter_size, modified_at]) => ({ name, model: name, modified_at, size: 1, details: { family, parameter_size } }));

let live = 0, max = 0, calls = 0;
const send = (res, code, body) => { res.writeHead(code, { 'content-type': 'application/json' }); res.end(JSON.stringify(body)); };

createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/api/tags') return send(res, 200, { models });
  if (req.method === 'GET' && req.url === '/_stats') return send(res, 200, { max, calls });
  if (req.method === 'POST' && req.url === '/api/generate') {
    let raw = '';
    req.on('data', (c) => { raw += c; });
    req.on('end', () => {
      let b = {};
      try { b = JSON.parse(raw); } catch {}
      if (b.stream !== false) return send(res, 400, { error: 'stub wants stream false' });
      if (!models.some((m) => m.name === b.model)) return send(res, 404, { error: `model '${b.model}' not found` });
      calls++; live++; max = Math.max(max, live);
      setTimeout(() => { live--; send(res, 200, { model: b.model, response: `${b.model}|${b.prompt}\n`, done: true }); },
        String(b.prompt).includes('slow') ? 300 : 60);
    });
    return;
  }
  send(res, 404, { error: 'not found' });
}).listen(0, '127.0.0.1', function () { writeFileSync(process.argv[2], String(this.address().port)); });
