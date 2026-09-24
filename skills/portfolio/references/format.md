# Record format and templates

Use only the four files below in `portfolio/`. Replace template tokens with evidence or an `[unknown: …]` prompt; omit unused entry templates. Use project-relative paths and explicit dates. Periods may be approximate if labelled. Commit timestamps indicate repository activity, not necessarily the date of research or a decision.

## context.md

A rough first draft of the case study, shaped like the user's portfolio pages, with working notes underneath. Write the draft in the first person, in the user's voice: warm, plain and modest, crediting collaborators by name. Aim for 250–500 words above Working notes. Tag every claim; turn gaps into visible `[unknown: …]` prompts rather than prose. Omit draft sections with nothing supported yet, except where an `[unknown: …]` prompt is worth keeping.

```markdown
# <Working title>

- **Description:** <One line.> [<confidence>]
- **Date:** <YYYY-MM, or range>
- **Role:** <The user's role.> [<confidence>]
- **Tags:** <design, build, research, writing, …>

## Media
- <Screenshot or recording worth capturing>: "<draft caption>"

<Intro, no heading: where, who with, the user's role, and the brief, in two to four sentences.>

## Challenge
<The problem, in one short paragraph.>

## Process
- <method or step, with counts where known>

## Solution
<What was made and the parts worth explaining.>

## Outcomes
- <before> → <after> [<confidence>]

## Learnings
- <what the user learned> [confirmed]

## Future iterations
- <what's next or unbuilt>

## Acknowledgements
<Role>: <name>

## Working notes

### Sharing
<What may be shown publicly. Unknown until confirmed; confirm before preparing external material.>

### Constraints
- <constraint> [<confidence>]

### Current state
<Present implementation and source.> [observed]

### Open questions
- <Only questions that materially improve the draft.>
```

Build Process from the timeline's milestones as methods, not a commit log. Outcomes only use evidence: measured or reported results, with the source in the tag; intended benefits are not outcomes. Learnings need the user's confirmation. Record the substance of a confirmation in the tag or text so future agents do not need that conversation. An explicit claim in a README is a documented claim, not independent confirmation of an outcome.

Add these sections to existing records when relevant; preserve existing content, decision IDs and milestone titles. No state-version change is needed.

## timeline.md

One card per milestone, oldest first: a heading with the title, then four bullets. No milestone IDs: the title identifies the entry, so keep it stable once written.

```markdown
# Project timeline

## <Title>

- **Date:** <YYYY-MM-DD, or start → end>
- **Change:** <What changed, one or two sentences.> [<confidence>]
- **Who:** <me, a collaborator, both, team, or Unknown; with a clause on the split if it helps.> [<confidence>]
- **References:** `<first>`…`<last>` · `<path>`, `<path>`
```

Example:

```markdown
## Hero reveal

- **Date:** 2026-09-23 → 09-24
- **Change:** Photo opens from a card on the child to the full frame; plain square entrance on phones; plays once per page, never on resize or return. [observed]
- **Who:** Me; co-designed in Figma with Sam. [confirmed]
- **References:** `037ab81`…`60f9570` · `src/components/Hero.astro`, `src/scripts/hero-entrance.ts`
```

- **Title:** two to five words.
- **Date:** mark approximate dates with `~`. Do not invent dates to force ordering.
- **Who:** name the user as the owner only when they have confirmed their role; commit author names alone are not enough.
- **References:** the milestone's first and last commits as short hashes (7+ characters), inclusive; unrelated commits may sit between them. Cite a single commit alone. Then the main files touched, project-relative. With no commits, cite a document or `user, <date>`.
- **Confidence:** tag claims with `[confirmed]`, `[observed]`, `[inferred]`, `[partial]` or `[unknown]`.

Keep other detail out of the card. Outcomes and lessons go in `context.md`, open questions in its Open questions section, and rationale in `decisions.md`, which links to milestones by title.

Provisional entries put `Uncommitted as of <date>` in Date, cite the observed paths in References, and must not imply delivery. When committed, add the commit hashes. If abandoned, remove the entry and tell the user briefly, unless the abandonment itself is significant.

## decisions.md

```markdown
# Project decisions

## D001: <Significant decision>

**Date:** <Known date, approximate date, or Unknown>
**Related milestone:** <timeline title, when applicable>

### Decision
<What was chosen; distinguish observed implementation from confirmed intent.>

### Context
<Supported circumstances.>

### Rationale
Unknown.

### Alternatives considered
Unknown.

### Evidence
- <Commit, file, documented discussion, or dated user confirmation>

### Confidence
<Claim-level labels, especially for rationale and alternatives.>
```

An earlier implementation proves that approach existed, not that it was formally evaluated as an alternative. Where a later decision reverses this one, link both IDs and keep the earlier rationale in historical context.

## state.json

```json
{
  "version": 1,
  "initialised_at": null,
  "last_reviewed_commit": null,
  "last_reviewed_at": null,
  "coverage_notes": []
}
```

On init replace timestamp nulls with actual UTC ISO 8601 timestamps. `last_reviewed_commit` is a full verified commit ID, or null when no Git commit has been reviewed. `last_reviewed_at` records init/update review time, not a read-only review. `coverage_notes` is an optional list of short strings describing missing history, limited scope, or unfinished review; clear resolved limitations. Do not duplicate milestones or unresolved product questions in JSON.

Save Markdown before advancing state. If interrupted, the old cursor lets the next update safely re-review and deduplicate. A no-op update may change the review timestamp and cursor while leaving Markdown untouched.
