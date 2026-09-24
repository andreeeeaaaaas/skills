# Portfolio

Use `/portfolio` to keep a record of your personal and work projects: what you contributed, the decisions you made, and the outcomes you can support with evidence. Over time, those records give you material for portfolio stories, CV examples, and career discussions. Your agent can reconstruct earlier work and add significant changes as you go.

## Installation

Keep one shared copy of this folder where your agents can read it. The skill needs `SKILL.md` and `references/format.md`. Setup instructions follow below; no command-line tool or service needs to run.

If your agent supports skill folders, copy or link this folder into its configured skills directory. Use links to the shared copy where possible so edits reach every agent.

You can also point agents to the skill through their instructions. Append the snippet below to the appropriate project or global instruction file: `AGENTS.md` for Codex and agents that read it, or `CLAUDE.md` for Claude Code. Keep any existing instructions.

Replace `<skill-path>` with the path to this folder. Use an absolute path for a shared copy on your machine. If you keep the skill inside a project at `skills/portfolio/`, use that relative path.

```markdown
## Portfolio

For Portfolio requests, read `<skill-path>/SKILL.md` and follow its
linked format reference. When the project root contains `portfolio/`,
load the skill and update the history at meaningful work checkpoints.
Only initialise tracking when asked. All agents should use the same
`portfolio/` files, with one agent writing at a time.
```

Configure each agent you use. For agents that do not read instruction files, attach `SKILL.md` and `references/format.md` or add them to project instructions. Give the agent access to the project and its `portfolio/` files. A chat-only AI can review files you supply; you will need to save its edits yourself.

Use one shared copy for local agents. Cloud accounts need their own setup; local installation does not upload the skill to them.

## Use

`/portfolio` updates an existing record or initialises one if absent. Slash-command support depends on your agent and setup. You can always ask in natural language:

- `/portfolio init` or “Initialise Portfolio for this project.” The agent reviews existing history before creating `portfolio/`.
- `/portfolio update` or “Update Portfolio since the last checkpoint.” The agent records significant changes and saves where it finished reviewing.
- `/portfolio review` or “Review Portfolio.” The agent summarises the history, uncertainties, and gaps without changing the files.

After the project, ask: “Use `portfolio/` to draft my portfolio narrative, preserving attribution and flagging unsupported claims.” Tracking does not write the narrative automatically.

For a review across projects, point the agent to the records you want it to use. Each project keeps its own four files:

```text
portfolio/
├── context.md
├── timeline.md
├── decisions.md
└── state.json
```

Your agent updates the history during a session when it has loaded the skill. There is no background tracking. Keep `portfolio/` available to every agent working on the project. The records are personal, so the agent will suggest ignoring `portfolio/` in Git if it isn't already. It does not edit `.gitignore`, commit or publish the files, or count its own edits as project milestones.

For work projects, keep internal evidence where your organisation allows it. Confirm what you can share before using it in a public portfolio. Record your contribution separately from the team’s work.

See [VALIDATION.md](VALIDATION.md) for the local smoke test and its limits.
