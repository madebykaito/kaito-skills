import http from 'node:http';
import fs from 'node:fs';
const server = http.createServer(async (req, res) => {
  let data = []; for await (const chunk of req) data.push(chunk);
  data = Buffer.concat(data);
  if (req.url === '/') { res.end('ok'); return; }
  if (req.headers.authorization !== 'test-key') { res.writeHead(401).end(); return; }
  res.setHeader('content-type', 'application/json');
  if (req.url === '/public/v1/integrations') return res.end(JSON.stringify([{id:'integration-1',identifier:'linkedin'}]));
  if (req.url === '/public/v1/upload') { fs.writeFileSync(process.env.FAKE_UPLOAD, data); return res.end(JSON.stringify({id:'media-1',path:'/uploads/media'})); }
  if (req.url === '/public/v1/posts') {
    fs.appendFileSync(process.env.FAKE_POSTS, data.toString() + '\n');
    if (process.env.FAKE_DROP) return req.socket.destroy();
    return res.end(JSON.stringify([{postId:'post-1',integration:'integration-1'}]));
  }
  res.writeHead(404).end();
});
server.listen(0, '127.0.0.1', () => fs.writeFileSync(process.env.FAKE_PORT, String(server.address().port)));
