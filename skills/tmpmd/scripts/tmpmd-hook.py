#!/usr/bin/env python3
"""Claude Code Stop hook for /tmpmd continuous mode.

When $TMPDIR/tmpmd/on/<session_id> exists, writes the last prompt and response
to $TMPDIR/tmpmd/<project>-continuous-<id>.md. Opens it on first write; Obsidian refreshes
the open tab on later writes. Never blocks or fails the session.
"""
import json
import os
import re
import subprocess
import sys

WORDS = 20


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n\n".join(b.get("text", "") for b in content if b.get("type") == "text")
    return ""


def clean_prompt(text):
    name = re.search(r"<command-name>(.*?)</command-name>", text, re.S)
    if name:
        args = re.search(r"<command-args>(.*?)</command-args>", text, re.S)
        text = name.group(1).strip() + (" " + args.group(1).strip() if args and args.group(1).strip() else "")
    text = re.sub(r"<system-reminder>.*?</system-reminder>", "", text, flags=re.S)
    words = text.split()
    return " ".join(words[:WORDS]) + ("..." if len(words) > WORDS else "")


def last_turn(transcript_path):
    rows = []
    with open(transcript_path) as f:
        for line in f:
            try:
                rows.append(json.loads(line))
            except ValueError:
                pass
    start = None
    for i, r in enumerate(rows):
        if r.get("type") == "user" and not r.get("isMeta") and (r.get("origin") or {}).get("kind") == "human":
            start = i
    if start is None:
        return "", ""
    prompt = clean_prompt(text_of((rows[start].get("message") or {}).get("content")))
    blocks = []
    for r in rows[start + 1:]:
        if r.get("type") == "assistant" and not r.get("isSidechain"):
            content = (r.get("message") or {}).get("content")
            blocks.extend(content if isinstance(content, list) else [{"type": "text", "text": content or ""}])
    last_tool = max((i for i, b in enumerate(blocks) if b.get("type") == "tool_use"), default=-1)
    response = "\n\n".join(b.get("text", "") for b in blocks[last_tool + 1:] if b.get("type") == "text")
    return prompt, response.strip()


def main():
    data = json.load(sys.stdin)
    session = data.get("session_id", "")
    base = os.path.join(os.environ.get("TMPDIR", "/tmp").rstrip("/"), "tmpmd")
    if not session or not os.path.exists(os.path.join(base, "on", session)):
        return
    prompt, response = last_turn(data.get("transcript_path", ""))
    lam = data.get("last_assistant_message")
    response = (lam if isinstance(lam, str) and lam.strip() else response).strip()
    if not response:
        return
    project = re.sub(r"[^\w.-]+", "-", os.path.basename((data.get("cwd") or "").rstrip("/"))).strip("-") or "session"
    path = os.path.join(base, f"{project}-continuous-{session[:8]}.md")
    is_new = not os.path.exists(path)
    with open(path, "w") as f:
        f.write((f"> {prompt}\n\n" if prompt else "") + response + "\n")
    if is_new:
        subprocess.run(["open", path], check=False)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
