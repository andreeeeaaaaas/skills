---
name: tmpmd
description: Save your last response, with the prompt that triggered it, to a temporary Markdown file and open it in the default Markdown app (Obsidian). Use for /tmpmd, or when the user asks to open, view or read the last output as Markdown.
---

# tmpmd

Write your previous response, headed by the prompt that triggered it, to a temporary `.md` file and open it.

1. Take your last response to the user, verbatim. Do not summarise, rewrite or add commentary. Leave out tool calls and tool output unless the response quoted them. If there is no previous response, say so and stop.
2. Take the user message that triggered that response. Keep its first 20 words and add `...` if you cut anything. Collapse line breaks into spaces.
3. Pick a short kebab-case slug (2 to 5 words) describing the content.
4. Write the file and open it in one command:

```bash
tmp="${TMPDIR:-/tmp}"; dir="${tmp%/}/tmpmd"; mkdir -p "$dir"
f="$dir/$(date +%Y%m%d-%H%M%S)-<slug>.md"
cat > "$f" <<'TMPMD_EOF'
> <truncated prompt>

<last response>
TMPMD_EOF
open "$f"
```

Keep the quoted `'TMPMD_EOF'` delimiter so `$`, backticks and backslashes in the response are written as-is. If the response contains a line that is exactly `TMPMD_EOF`, use a different delimiter. If your host has a file-writing tool, you can write the file with it instead and then run `open`.

On Linux use `xdg-open` instead of `open`.

5. Reply with only the file path.

If the user passes text after `/tmpmd`, write that text instead of the last response and leave out the prompt line.
