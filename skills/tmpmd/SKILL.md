---
name: tmpmd
description: Save your last response to a temporary Markdown file and open it in the default Markdown app (Obsidian). Use for /tmpmd, or when the user asks to open, view or read the last output as Markdown.
---

# tmpmd

Write your previous response to a temporary `.md` file and open it.

1. Take your last response to the user, verbatim. Do not summarise, rewrite or add commentary. Leave out tool calls and tool output unless the response quoted them. If there is no previous response, say so and stop.
2. Pick a short kebab-case slug (2 to 5 words) describing the content.
3. Write the file and open it in one command:

```bash
tmp="${TMPDIR:-/tmp}"; dir="${tmp%/}/tmpmd"; mkdir -p "$dir"
f="$dir/$(date +%Y%m%d-%H%M%S)-<slug>.md"
cat > "$f" <<'TMPMD_EOF'
<last response>
TMPMD_EOF
open "$f"
```

Keep the quoted `'TMPMD_EOF'` delimiter so `$`, backticks and backslashes in the response are written as-is. If the response contains a line that is exactly `TMPMD_EOF`, use a different delimiter. If your host has a file-writing tool, you can write the file with it instead and then run `open`.

On Linux use `xdg-open` instead of `open`.

4. Reply with only the file path.

If the user passes text after `/tmpmd`, write that text instead of the last response.
