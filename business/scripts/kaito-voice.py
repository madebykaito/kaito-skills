#!/usr/bin/env python3
"""Summarize writing patterns from an owner's sent mailbox without saving messages."""
import argparse
import collections
import mailbox
import os
import re
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('export', help='mbox file or Maildir directory containing sent mail')
p.add_argument('--owner', required=True)
a = p.parse_args()
if not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', a.owner) or len(a.owner) > 64:
    p.error('invalid owner id')
root = Path(os.environ.get('KAITO_HOME', Path.home() / '.kaito')) / 'owners' / a.owner
if not (root / 'owner.json').is_file():
    p.error('owner not found')
source = Path(a.export)
if not source.exists():
    p.error('mail export not found')
box = mailbox.Maildir(source, create=False) if source.is_dir() else mailbox.mbox(source, create=False)
lengths, sentences = [], []
for msg in box:
    parts = msg.walk() if msg.is_multipart() else [msg]
    for part in parts:
        if part.get_content_type() != 'text/plain' or part.get_content_disposition() == 'attachment':
            continue
        raw = part.get_payload(decode=True)
        if raw is None:
            continue
        text = raw.decode(part.get_content_charset() or 'utf-8', errors='replace')
        text = re.split(r'(?m)^(?:On .+ wrote:|>+|-- $)', text)[0]
        words = re.findall(r'\b\w+\b', text, flags=re.UNICODE)
        if words:
            lengths.append(len(words))
            sentences.extend(len(re.findall(r'\b\w+\b', s)) for s in re.split(r'[.!?]+', text) if re.search(r'\w', s))
        break
box.close()
if not lengths:
    p.error('no plain-text messages found')
profile = f'# Voice profile\n\nBased on {len(lengths)} sent messages. Review before use; counts are only a starting point.\n\n- Average message length: {round(sum(lengths)/len(lengths))} words.\n- Average sentence length: {round(sum(sentences)/len(sentences))} words.\n- Common message length: {collections.Counter("short (under 50 words)" if n < 50 else "medium (50 to 149 words)" if n < 150 else "long (150 or more words)" for n in lengths).most_common(1)[0][0]}.\n'
out = root / 'voice.md'
if out.exists():
    p.error('voice.md already exists; move or review it before generating a replacement')
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w', encoding='utf-8') as f:
    f.write(profile)
print(f'voice={out}\nmessages={len(lengths)}')
