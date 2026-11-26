"""Local SMTP and HTTP test peers. Only the loopback address is bound."""
import base64
import hashlib
import hmac
import json
import socketserver
import sys
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler
from pathlib import Path

mode, root = sys.argv[1], Path(sys.argv[2])


def delivered():
    with (root / "delivered").open("a") as fh:
        print(mode, file=fh)


def check_mime(raw):
    message = BytesParser(policy=policy.default).parsebytes(raw)
    assert message["From"].addresses[0].addr_spec == "tea@example.test"
    assert message["To"].addresses[0].addr_spec == "guest@example.test"
    assert message["Subject"] == "Tea {{special}}"
    assert message["List-Unsubscribe"] == "<https://example.test/leave>"
    assert message["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
    assert message.get_body().get_payload(decode=True) == b"Tea & cakes {{literal}}\n"
    attachment, = message.iter_attachments()
    assert attachment.get_filename() == "menu.txt"
    assert attachment.get_payload(decode=True) == b"attachment bytes"


class Smtp(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b"220 loopback test sink\r\n")
        while line := self.rfile.readline():
            verb = line.split(None, 1)[0].upper()
            if verb == b"MAIL":
                assert line.lower().startswith(b"mail from:<tea@example.test>")
            if verb == b"RCPT":
                assert line.lower().startswith(b"rcpt to:<guest@example.test>")
                if (root / "refuse").exists():
                    self.wfile.write(b"550 mailbox unavailable\r\n")
                    continue
            if verb == b"DATA":
                self.wfile.write(b"354 send message\r\n")
                data = []
                while (part := self.rfile.readline()) not in (b".\r\n", b""):
                    data.append(part[1:] if part.startswith(b"..") else part)
                if not part:
                    return
                check_mime(b"".join(data))
                delivered()
                if mode == "smtp-drop":
                    return
            self.wfile.write(b"250 ok\r\n")


class Http(BaseHTTPRequestHandler):
    def respond(self, obj):
        body = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        assert mode == "listmonk"
        assert self.path == "/api/templates/7"
        assert base64.b64decode(self.headers["Authorization"].split()[1]) == b"fixture:dummy-token"
        self.respond({"data": {"id": 7, "type": "tx", "body": "{{ Safe .Tx.Data.body }}"}})

    def do_POST(self):
        raw = self.rfile.read(int(self.headers["Content-Length"]))
        if mode == "ses":
            assert self.path == "/v2/email/outbound-emails"
            self.check_sigv4(raw)
            request = json.loads(raw)
            assert request["FromEmailAddress"] == "tea@example.test"
            assert request["Destination"]["ToAddresses"] == ["guest@example.test"]
            check_mime(base64.b64decode(request["Content"]["Raw"]["Data"]))
            delivered()
            self.respond({"MessageId": "fake-ses-id"})
        else:
            assert self.path == "/api/tx"
            assert base64.b64decode(self.headers["Authorization"].split()[1]) == b"fixture:dummy-token"
            mime = f"Content-Type: {self.headers['Content-Type']}\r\n\r\n".encode() + raw
            data, attachment = BytesParser(policy=policy.default).parsebytes(mime).iter_parts()
            request = json.loads(data.get_payload())
            assert request["subscriber_mode"] == "external"
            assert request["subscriber_emails"] == ["guest@example.test"]
            assert request["from_email"] == "tea@example.test"
            assert request["template_id"] == 7
            assert request["subject"] == "{{ .Tx.Data.subject }}"
            assert request["data"] == {"body": "Tea & cakes {{literal}}\n", "subject": "Tea {{special}}"}
            assert request["content_type"] == "plain"
            assert {"List-Unsubscribe": "<https://example.test/leave>"} in request["headers"]
            assert {"List-Unsubscribe-Post": "List-Unsubscribe=One-Click"} in request["headers"]
            assert attachment.get_filename() == "menu.txt"
            assert attachment.get_payload(decode=True) == b"attachment bytes"
            delivered()
            self.respond({"data": True})

    def check_sigv4(self, body):
        scheme, auth = self.headers["Authorization"].split(" ", 1)
        assert scheme == "AWS4-HMAC-SHA256"
        fields = dict(field.split("=", 1) for field in auth.split(", "))
        date = self.headers["X-Amz-Date"]
        scope = f"{date[:8]}/us-east-1/ses/aws4_request"
        assert fields["Credential"] == "fixture/" + scope
        assert self.headers["X-Amz-Security-Token"] == "dummy-session"
        names = "content-type;host;x-amz-content-sha256;x-amz-date;x-amz-security-token"
        assert fields["SignedHeaders"] == names
        body_hash = hashlib.sha256(body).hexdigest()
        assert self.headers["X-Amz-Content-Sha256"] == body_hash
        head = "\n".join(f"{name}:{self.headers[name]}" for name in names.split(";"))
        canonical = "\n".join(["POST", self.path, "", head, "", names, body_hash])
        string = "\n".join([scheme, date, scope, hashlib.sha256(canonical.encode()).hexdigest()])
        secret = b"AWS4dummy-secret"
        for part in scope.split("/"):
            secret = hmac.digest(secret, part.encode(), "sha256")
        assert fields["Signature"] == hmac.digest(secret, string.encode(), "sha256").hex()


# HTTPServer also resolves a server name, which the loopback fixture does not use.
sink = socketserver.TCPServer(("127.0.0.1", 0), Smtp if mode.startswith("smtp") else Http)
port = sink.server_address[1]
url = f"http://127.0.0.1:{port}"
if mode.startswith("smtp"):
    config = {"host": "127.0.0.1", "port": port, "tls": "none"}
elif mode == "ses":
    config = {"url": url, "region": "us-east-1", "access_key_id": "fixture",
              "secret_access_key": "dummy-secret", "session_token": "dummy-session"}
else:
    config = {"url": url, "username": "fixture", "token": "dummy-token"}
temp = root / "engine.tmp"
temp.write_text(json.dumps(config))
temp.replace(root / "engine.json")
temp = root / "mail.port.tmp"
temp.write_text(f"{port}\n")
temp.replace(root / "mail.port")
sink.serve_forever()
