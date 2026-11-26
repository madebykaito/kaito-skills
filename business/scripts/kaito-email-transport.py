"""Private transport for kaito-email.mjs. The caller verifies and claims the ledger ref."""
import base64
import contextlib
import datetime
import hashlib
import hmac
import http.client
import json
import re
import smtplib
import ssl
import sys
import uuid
from email import policy
from email.message import EmailMessage
from email.utils import formatdate
from urllib.parse import urlsplit

LOOPBACK = {"localhost", "127.0.0.1", "::1"}
PASSTHROUGH = "{{ Safe .Tx.Data.body }}"
SES_PATH = "/v2/email/outbound-emails"
TIMEOUT = 12


class Uncertain(Exception):
    pass


def b64(data):
    return base64.b64encode(data).decode("ascii")


def json_bytes(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def mail_headers(message):
    headers = {}
    if message["unsubscribe"]:
        headers["List-Unsubscribe"] = "<" + message["unsubscribe"] + ">"
    if message["one_click"]:
        headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    if message["in_reply_to"]:
        headers["In-Reply-To"] = message["in_reply_to"]
        headers["References"] = message["in_reply_to"]
    return headers


def mime(message, files, message_id):
    mail = EmailMessage(policy=policy.SMTP)
    mail["From"] = message["from"]
    mail["To"] = message["to"]
    mail["Subject"] = message["subject"]
    mail["Message-ID"] = message_id
    mail["Date"] = formatdate(usegmt=True)
    for name, value in mail_headers(message).items():
        mail[name] = value
    mail.set_content(message["body"].encode(), maintype="text", subtype="plain", cte="base64")
    mail.set_param("charset", "utf-8")
    for name, data in files:
        mail.add_attachment(data, maintype="application", subtype="octet-stream", filename=name)
    return mail.as_bytes()


def smtp_send(config, message, data):
    host = config["host"]
    mode = config.get("tls", "starttls")
    port = config.get("port", 465 if mode == "implicit" else 587)
    if mode not in {"implicit", "starttls", "none"} or (mode == "none" and host not in LOOPBACK):
        raise ValueError("SMTP requires TLS except on loopback")
    if mode == "none":
        # The loopback SMTP peer has no need for a system hostname lookup or TLS context.
        client = smtplib.SMTP(host, port, local_hostname="localhost", timeout=TIMEOUT)
    else:
        context = ssl.create_default_context()
        if mode == "implicit":
            client = smtplib.SMTP_SSL(host, port, timeout=TIMEOUT, context=context)
        else:
            client = smtplib.SMTP(host, port, timeout=TIMEOUT)
    try:
        client.ehlo_or_helo_if_needed()
        if mode == "starttls":
            client.starttls(context=context)
            client.ehlo()
        if config.get("username") or config.get("password"):
            if mode == "none":
                raise ValueError("SMTP credentials require TLS")
            client.login(config["username"], config["password"])
        options = ["SIZE=" + str(len(data))] if client.has_extn("size") else []
        code, _ = client.mail(message["from"], options)
        if code != 250:
            raise ValueError("SMTP sender rejected")
        code, _ = client.rcpt(message["to"])
        if code not in {250, 251}:
            raise ValueError("SMTP recipient rejected")
        try:
            code, _ = client.data(data)
        except smtplib.SMTPDataError:
            raise  # DATA itself was refused before bytes went out.
        except (OSError, smtplib.SMTPException) as exc:
            raise Uncertain() from exc
        if 400 <= code < 600:
            raise ValueError("SMTP message rejected")
        if code != 250:
            raise Uncertain()
    finally:
        with contextlib.suppress(OSError):
            client.close()


def request(method, base, resource, body=None, headers=None):
    url = urlsplit(base)
    if (not url.hostname or url.username is not None or url.query or url.fragment
            or url.scheme not in {"https", "http"} or (url.scheme == "http" and url.hostname not in LOOPBACK)):
        raise ValueError("mail API needs HTTPS except on loopback")
    if url.scheme == "https":
        conn = http.client.HTTPSConnection(url.hostname, url.port, timeout=TIMEOUT)
    else:
        conn = http.client.HTTPConnection(url.hostname, url.port, timeout=TIMEOUT)
    try:
        conn.connect()
        try:
            conn.request(method, url.path.rstrip("/") + resource, body, headers or {})
            response = conn.getresponse()
            if not 200 <= response.status < 300:
                if method == "POST" and (not 400 <= response.status < 500 or response.status in {408, 409}):
                    raise Uncertain()
                raise ValueError("mail API rejected the request")
            data = response.read(1024 * 1024 + 1)
            if len(data) > 1024 * 1024:
                if method == "POST":
                    raise Uncertain()
                raise ValueError("oversize mail API response")
            return json.loads(data)
        except (OSError, http.client.HTTPException, UnicodeError, json.JSONDecodeError) as exc:
            if method == "POST":
                raise Uncertain() from exc
            raise
    finally:
        conn.close()


def signed_headers(config, host, body):
    region = config["region"]
    now = datetime.datetime.now(datetime.timezone.utc)
    stamp, day = now.strftime("%Y%m%dT%H%M%SZ"), now.strftime("%Y%m%d")
    body_hash = hashlib.sha256(body).hexdigest()
    headers = {
        "content-type": "application/json",
        "host": host,
        "x-amz-date": stamp,
        "x-amz-content-sha256": body_hash,
    }
    if config.get("session_token"):
        headers["x-amz-security-token"] = config["session_token"]
    keys = sorted(headers)
    signed = ";".join(keys)
    canonical_headers = "".join(f"{key}:{' '.join(headers[key].split())}\n" for key in keys)
    canonical = f"POST\n{SES_PATH}\n\n{canonical_headers}\n{signed}\n{body_hash}"
    scope = f"{day}/{region}/ses/aws4_request"
    to_sign = f"AWS4-HMAC-SHA256\n{stamp}\n{scope}\n{hashlib.sha256(canonical.encode()).hexdigest()}"
    key = ("AWS4" + config["secret_access_key"]).encode()
    for field in (day, region, "ses", "aws4_request"):
        key = hmac.digest(key, field.encode(), "sha256")
    signature = hmac.new(key, to_sign.encode(), "sha256").hexdigest()
    headers["authorization"] = (
        f"AWS4-HMAC-SHA256 Credential={config['access_key_id']}/{scope}, "
        f"SignedHeaders={signed}, Signature={signature}"
    )
    return headers


def ses_send(config, message, data):
    region = config["region"]
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)+", region):
        raise ValueError("invalid SES region")
    suffix = "amazonaws.com.cn" if region.startswith("cn-") else "amazonaws.com"
    base = config.get("url", f"https://email.{region}.{suffix}")
    url = urlsplit(base)
    if url.path not in {"", "/"}:
        raise ValueError("SES URL must be an origin")
    body = json_bytes({
        "FromEmailAddress": message["from"],
        "Destination": {"ToAddresses": [message["to"]]},
        "Content": {"Raw": {"Data": b64(data)}},
    })
    response = request("POST", base, SES_PATH, body, signed_headers(config, url.netloc, body))
    remote = response.get("MessageId") if isinstance(response, dict) else None
    if not isinstance(remote, str) or not remote:
        raise Uncertain()
    return remote


def multipart(payload, files):
    boundary = uuid.uuid4().hex
    parts = [
        f'--{boundary}\r\nContent-Disposition: form-data; name="data"\r\n\r\n'.encode(),
        payload, b"\r\n",
    ]
    for name, data in files:
        name = name.replace('"', r'\"')
        parts.extend([
            (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{name}"\r\n'
             "Content-Type: application/octet-stream\r\n\r\n").encode(),
            data, b"\r\n",
        ])
    parts.append(f"--{boundary}--\r\n".encode())
    return f"multipart/form-data; boundary={boundary}", b"".join(parts)


def listmonk_send(config, message, files, ref):
    if not config["username"] or not config["token"]:
        raise ValueError("missing listmonk credentials")
    auth = "Basic " + b64(f"{config['username']}:{config['token']}".encode())
    base = config["url"]
    template = request("GET", base, f"/api/templates/{message['template']}", headers={"Authorization": auth})["data"]
    if template["type"] != "tx" or template["body"] != PASSTHROUGH:
        raise ValueError("listmonk template must be the dedicated plain-text pass-through")
    headers = {**mail_headers(message), "X-Kaito-Ref": ref}
    payload = json_bytes({
        "subscriber_mode": "external", "subscriber_emails": [message["to"]],
        "template_id": message["template"], "from_email": message["from"],
        "subject": "{{ .Tx.Data.subject }}", "content_type": "plain",
        "data": {"body": message["body"], "subject": message["subject"]},
        "headers": [{key: value} for key, value in headers.items()],
    })
    content_type, body = multipart(payload, files) if files else ("application/json", payload)
    response = request("POST", base, "/api/tx", body, {"Authorization": auth, "Content-Type": content_type})
    if not isinstance(response, dict) or response.get("data") is not True:
        raise Uncertain()


def main():
    data = json.load(sys.stdin)
    msg, cfg = data["message"], data["config"]
    files = list(zip(msg["attachments"], map(base64.b64decode, data["attachments"])))
    message_id = f"<{data['opKey']}@{msg['from'].split('@')[1]}>"
    try:
        if msg["engine"] == "listmonk":
            listmonk_send(cfg, msg, files, data["ref"])
            result = {"result": "ok"}
        else:
            raw = mime(msg, files, message_id)
            if msg["engine"] == "smtp":
                smtp_send(cfg, msg, raw)
                remote = message_id
            else:
                remote = ses_send(cfg, msg, raw)
            result = {"result": "ok", "remote": remote}
    except Uncertain:
        result = {"result": "uncertain"}
    except Exception:
        # Transport errors can contain credentials, addresses or message content.
        result = {"result": "failed"}
    print(json.dumps(result))


if __name__ == "__main__":
    main()
