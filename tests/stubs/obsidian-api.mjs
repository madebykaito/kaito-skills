// Fake Obsidian Local REST API. node obsidian-api.mjs <record-file> <status> <port-file>
import { createServer } from 'node:http';
import { writeFileSync, appendFileSync } from 'node:fs';
const [rec, status = '204', portFile] = process.argv.slice(2);
createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    appendFileSync(rec, JSON.stringify({ method: req.method, path: req.url, headers: req.headers, body }) + '\n');
    res.statusCode = Number(status);
    res.end();
  });
}).listen(0, '127.0.0.1', function () { writeFileSync(portFile, String(this.address().port)); });
