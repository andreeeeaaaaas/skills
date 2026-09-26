---
name: tmpmd
description: Save your last response, with the prompt that triggered it, to a temporary Markdown file and open it in the default Markdown app (Obsidian). Use for /tmpmd, /tmpmd on, /tmpmd off, or when the user asks to open, view or read the last output as Markdown.
---

# tmpmd

Write your previous response, headed by the prompt that triggered it, to a temporary `.md` file and open it.

1. Take your last response to the user, verbatim. Do not summarise, rewrite or add commentary. Leave out tool calls and tool output unless the response quoted them. If there is no previous response, say so and stop.
2. Take the user message that triggered that response. Keep its first 20 words and add `...` if you cut anything. Collapse line breaks into spaces.
3. Write the file and open it in one command:

```bash
tmp="${TMPDIR:-/tmp}"; dir="${tmp%/}/tmpmd"; mkdir -p "$dir"
p=$(printf %s "${PWD##*/}" | tr -cs 'A-Za-z0-9._-' '-'); s="${CLAUDE_CODE_SESSION_ID:0:8}"
f="$dir/tmpmd-$p-${s:-$(date +%Y%m%d-%H%M%S)}.md"
cat > "$f" <<'TMPMD_EOF'
> <truncated prompt>

<last response>
TMPMD_EOF
open "$f"
```

Keep the quoted `'TMPMD_EOF'` delimiter so `$`, backticks and backslashes in the response are written as-is. If the response contains a line that is exactly `TMPMD_EOF`, use a different delimiter. If your host has a file-writing tool, you can write the file with it instead and then run `open`.

The file is named `tmpmd-<project>-<session>.md`, so each `/tmpmd` in a session overwrites the last one and the open tab refreshes. Without a session ID (other agents), a timestamp replaces it.

On Linux use `xdg-open` instead of `open`.

4. Reply with only the file path.

If the user passes text after `/tmpmd` (other than `on` or `off`), write that text instead of the last response and leave out the prompt line.

## Continuous mode (Claude Code only)

A Stop hook (`scripts/tmpmd-hook.py`, registered in `~/.claude/settings.json`) rewrites one file per session, `$TMPDIR/tmpmd/tmpmd-c-<project>-<session>.md`, after every response. It opens the file on first write; Obsidian refreshes the open tab after that.

- `/tmpmd on`: run the command below, then reply with only `tmpmd on`. The file opens straight away and updates after each response.
  ```bash
  tmp="${TMPDIR:-/tmp}"; mkdir -p "${tmp%/}/tmpmd/on" && touch "${tmp%/}/tmpmd/on/$CLAUDE_CODE_SESSION_ID"
  ```
- `/tmpmd off`: run the command below, then reply with only `tmpmd off`.
  ```bash
  tmp="${TMPDIR:-/tmp}"; rm -f "${tmp%/}/tmpmd/on/$CLAUDE_CODE_SESSION_ID"
  ```
- If the user closed the tab, reopen it with `open "${TMPDIR%/}"/tmpmd/tmpmd-c-*-"${CLAUDE_CODE_SESSION_ID:0:8}".md`.
- If notes stop updating, read `$TMPDIR/tmpmd/hook.log`. It holds the hook's latest error, such as a transcript format change.

In other agents, or if `$CLAUDE_CODE_SESSION_ID` is empty, say continuous mode needs the Claude Code hook and stop.
