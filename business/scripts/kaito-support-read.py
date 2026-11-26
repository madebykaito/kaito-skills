"""Read an inbox without setting flags or modifying the source mailbox."""
import hashlib
import imaplib
import json
import mailbox
import ssl
import sys
from email import policy
from email.parser import BytesParser
from email.utils import parsedate_to_datetime
from pathlib import Path

MAX_BYTES = 5 * 1024 * 1024


def maildir(path, limit):
    root = Path(path)
    if not all((root / part).is_dir() for part in ("cur", "new")):
        raise ValueError("invalid Maildir")
    files = [file for part in ("cur", "new") for file in (root / part).iterdir()
             if not file.name.startswith(".") and file.is_file() and not file.is_symlink()]
    for file in sorted(files, key=lambda f: (f.stat().st_mtime_ns, f.name), reverse=True)[:limit]:
        with file.open("rb") as stream:
            yield stream.read(MAX_BYTES + 1)


def mbox(path, limit):
    box = mailbox.mbox(path, create=False)
    try:
        for key in box.keys()[-limit:][::-1]:
            with box.get_file(key) as stream:
                yield stream.read(MAX_BYTES + 1)
    finally:
        box.close()


def imap(config, limit):
    with imaplib.IMAP4_SSL(config["host"], config.get("port", 993),
                         ssl_context=ssl.create_default_context(), timeout=12) as box:
        box.login(config["username"], config["password"])
        folder = config.get("mailbox", "INBOX").replace("\\", "\\\\").replace('"', r'\"')
        if box.select(f'"{folder}"', readonly=True)[0] != "OK":
            raise ValueError("cannot open IMAP folder")
        status, data = box.uid("SEARCH", None, "ALL")
        if status != "OK":
            raise ValueError("IMAP search failed")
        for uid in data[0].split()[-limit:][::-1]:
            status, response = box.uid("FETCH", uid, f"(BODY.PEEK[]<0.{MAX_BYTES + 1}>)")
            if status != "OK":
                raise ValueError("IMAP fetch failed")
            for part in response:
                if isinstance(part, tuple):
                    yield part[1]
                    break


def single_address(header):
    if header is None or header.defects or len(header.addresses) != 1:
        return None
    address = header.addresses[0]
    return {"name": address.display_name, "email": address.addr_spec}


def summarize(raw):
    truncated = len(raw) > MAX_BYTES
    message = BytesParser(policy=policy.default).parsebytes(raw if not truncated else raw.split(b"\r\n\r\n", 1)[0].split(b"\n\n", 1)[0])
    from_ = single_address(message["From"]) if len(message.get_all("From", [])) == 1 else None
    reply_to = message.get_all("Reply-To", [])
    reply = single_address(reply_to[0]) if len(reply_to) == 1 else (from_ if not reply_to else None)
    body = message.get_body(preferencelist=("plain",)) if not truncated else None
    try:
        date = parsedate_to_datetime(str(message["Date"]))
        timestamp = int(date.timestamp()) if date.tzinfo is not None else 0
    except (ValueError, TypeError, OverflowError):
        timestamp = 0
    try:
        text = body.get_content(errors="replace") if body is not None else ""
    except (LookupError, UnicodeError):
        text = ""
    ids = message.get_all("Message-ID", [])
    return {
        "fingerprint": hashlib.sha256(raw).hexdigest(),
        "message_id": str(ids[0]).strip() if len(ids) == 1 else "",
        "customer": from_, "reply_to": reply, "subject": str(message.get("Subject", "")),
        "timestamp": timestamp, "text": text[:16000],
    }


def main():
    params = json.load(sys.stdin)
    source, limit = params["source"], params["limit"]
    try:
        if source == "maildir":
            messages = maildir(params["path"], limit)
        elif source == "mbox":
            messages = mbox(params["path"], limit)
        else:
            messages = imap(params["config"], limit)
        print(json.dumps([summarize(raw) for raw in messages]))
    except Exception:
        # Credentials and private headers can appear in protocol errors.
        sys.exit(1)


if __name__ == "__main__":
    main()
