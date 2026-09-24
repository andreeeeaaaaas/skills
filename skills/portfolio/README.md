---
---
# Portfolio

Use `/portfolio` to record contributions, decisions, and supported outcomes across personal and work projects. Your agent reconstructs earlier work and records significant changes as you go, giving you material for case studies, CVs, and career discussions.

## Installation

Keep a shared copy of this folder, including `SKILL.md` and `references/format.md`, where your local agents can read it. No service or command-line tool is required.

For agents that support skill folders, link or copy this folder into each agent’s skills directory. Links keep agents using the same copy.

You can also append this snippet to your project or global instructions: `AGENTS.md` for Codex, or `CLAUDE.md` for Claude Code. Keep existing instructions.

Replace `<skill-path>` with an absolute path to the shared copy, or `skills/portfolio` if stored in the project.

```markdown
## Portfolio

For Portfolio requests, read `<skill-path>/SKILL.md` and follow its
linked format reference. When the project root contains `portfolio/`,
load the skill and update the history at meaningful work checkpoints.
Only initialise tracking when asked. All agents should use the same
`portfolio/` files, with one agent writing at a time.
```

Configure each agent, including cloud accounts, separately. If an agent cannot read local instructions, attach `SKILL.md` and `references/format.md` or add them to its project instructions. Give it access to the project and its `portfolio/` files. For chat-only AI, supply the files and save its edits yourself.

## Use

`/portfolio` updates an existing record or creates one. Slash-command support varies by agent; you can also ask in plain language:

- `/portfolio init` or “Initialise Portfolio for this project.” Reviews project history before creating `portfolio/`.
- `/portfolio update` or “Update Portfolio since the last checkpoint.” Records significant changes and saves the review checkpoint.
- `/portfolio review` or “Review Portfolio.” Summarises history, uncertainties, and gaps without changing files.

To turn the records into a narrative, ask: “Use `portfolio/` to draft my portfolio narrative, preserving attribution and flagging unsupported claims.” Tracking does not draft it automatically.

## Records

Each project keeps four files. For a review across projects, point the agent to the records to use.

```text
portfolio/
├── context.md
├── timeline.md
├── decisions.md
└── state.json
```

Updates happen during sessions with the skill loaded; there is no background tracking. Give every agent access to the same `portfolio/` folder.

The records are personal. The agent suggests ignoring `portfolio/` in Git if needed, but does not edit `.gitignore`, commit or publish records, or count record edits as project milestones.

For work projects, store evidence only where your organisation allows, confirm what you can share publicly, and distinguish your contribution from the team’s work.

See [VALIDATION.md](VALIDATION.md) for the local smoke test and its limits.
