# Portfolio

Use `/portfolio` to record contributions, decisions, and key context over time across personal and work projects.

When initialised, your agent summarises earlier work and can then record significant changes as you go, giving you material for case studies, CVs, and career discussions. The skill creates and updates records across three editable `.md` files.

Most useful for projects involving Git, long-running chats, or files connected to a repository.

## Setup

Follow the [installation instructions](../../README.md#install), then give your AI access to the project or supply the relevant files and notes.

## Use

Ask your AI:

- **“Initialise Portfolio for this project.”** Review existing evidence and create the records.
- **“Update Portfolio.”** Record significant changes since the last review.
- **“Review Portfolio.”** Summarise contributions, outcomes and gaps without changing the records.

Where slash commands are supported, use `/portfolio init`, `/portfolio update` or `/portfolio review`.

To draft a case study, ask: “Use these records to draft my portfolio narrative. Preserve attribution and flag unsupported claims.”

## What it saves

Each project keeps its own records:

```text
portfolio/
├── context.md
├── timeline.md
├── decisions.md
└── state.json
```

These hold the project context, milestones, decisions and review checkpoint. Unsupported claims stay marked as unknown.

When one repository holds several projects, such as a monorepo or a collection of skills, each gets its own named record:

```text
portfolio/
├── app/
│   ├── context.md
│   └── …
└── website/
    ├── context.md
    └── …
```

Name the project when you ask, for example: “Initialise Portfolio for the website.”

For a review across projects, supply each project’s records.

## Optional checkpoint tracking

To encourage updates during project work, add this to your AI’s persistent instructions, such as `AGENTS.md`, `CLAUDE.md` or project instructions:

```text
When this project contains portfolio/, follow the Portfolio skill
at meaningful work checkpoints. Read its SKILL.md and linked format
reference. Only initialise tracking when asked. Preserve existing
records and allow one writer at a time.
```

Make sure each AI can access the skill and the same records. Updates happen during active sessions; there is no background tracking.

## Privacy

Keep records private unless you choose to share them. For work projects, follow your organisation’s storage and sharing rules, and distinguish your contribution from the team’s work.

See [validation results and limits](VALIDATION.md).
