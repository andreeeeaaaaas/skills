# tmpmd

Use `/tmpmd` to read your agent's last answer somewhere nicer than the terminal.

Your agent saves its last answer, headed by the prompt that triggered it, to a temporary Markdown file and opens it in your default Markdown app, such as Obsidian. Files live in your system's temp folder, so nothing is added to your notes or vault.

Most useful for long answers, plans and write-ups you want to read properly or keep open while you work.

## Setup

Follow the [installation instructions](../../README.md#install). Make sure a Markdown app is set as the default for `.md` files.

## Use

Ask your AI:

- **“/tmpmd”** Save and open the last answer.
- **“/tmpmd `<text>`”** Save and open that text instead.
- **“/tmpmd on”** Update one note after every answer for the rest of the session (Claude Code only).
- **“/tmpmd off”** Stop updating the note.

Each note starts with the prompt, cut to 20 words, followed by the full answer. Running `/tmpmd` again in the same session replaces the note, and the open tab refreshes.

## What it saves

Notes go to your system's temp folder, named by project folder and session:

```text
$TMPDIR/tmpmd/
├── tmpmd-<project>-<session>.md     # /tmpmd
└── tmpmd-c-<project>-<session>.md   # /tmpmd on
```

On macOS, temp files are removed after a few days unused. Copy a note into your vault if you want to keep it.

## Continuous mode setup

`/tmpmd on` relies on a Claude Code Stop hook that rewrites the note after each answer. Add it to `~/.claude/settings.json`, pointing at wherever the skill is installed:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "python3 ~/.claude/skills/tmpmd/scripts/tmpmd-hook.py",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

The hook does nothing until `/tmpmd on` is used in a session. It reads the session transcript, whose format Claude Code may change. If the note stops updating, check `$TMPDIR/tmpmd/hook.log`.

## Privacy

Notes can contain anything your agent wrote, including file contents. They stay on your machine in a temp folder only you can read, and are not synced unless you move them.
