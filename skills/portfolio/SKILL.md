---
name: portfolio
description: Build an evidence-backed record of personal and work projects, contributions, decisions, and outcomes in portfolio/ for later portfolio narratives and career discussions. Use for /portfolio init, update, checkpoint, or review, and meaningful checkpoints where tracking is active.
---

# Portfolio

Record the project at the level its creator would explain it to another designer or developer, not at the level Git records it. Build a record of the user’s work over time: what changed, what they contributed, what they learned, and what outcomes the evidence supports. Cover personal and work projects, including design, research, and collaboration when sources are available. These records support later portfolio narratives, CV examples, and career discussions. `context.md` is a rough first draft of the case study, in the user's voice, for them to iterate on at the end. Keep it plain: no marketing language, no invented claims, and gaps left visible.

Use standard filesystem, Git, Markdown, and JSON capabilities. Use `/portfolio init`, `/portfolio update` (also `checkpoint`), and `/portfolio review` as workflow shorthand, or accept the same requests in natural language. Slash-command availability depends on the host agent and installation; these names do not create executable commands. For `/portfolio` alone, update an existing record or initialise one if absent.

## Shared record

Store all project history in the project root's `portfolio/`: `context.md`, `timeline.md`, `decisions.md`, and `state.json`. Read [references/format.md](references/format.md) before creating or changing records. Markdown is authoritative; JSON holds only review state. Preserve human edits, milestone titles and decision IDs.

When one repository holds several distinct projects, such as a monorepo or a collection of skills, keep one named record per project in `portfolio/<name>/`, using a short kebab-case name. Each named record has the same four files and its own state, with `scope` listing the project-relative paths it covers. Use plain `portfolio/` for a repository that is one project. Do not mix the two layouts: if a single record exists and the user starts tracking a second project, offer to move the existing record into `portfolio/<name>/` first. Wherever these instructions say `portfolio/`, apply them to the relevant named record.

The folder is visible, not hidden. A legacy hidden `.portfolio/` is the same record: use it, and offer to rename it to `portfolio/` rather than creating a second record.

The records are personal. In a Git repository, check whether `portfolio/` is ignored (`git check-ignore -q portfolio/`). If not, tell the user and suggest adding `portfolio/` to `.gitignore`, or to `.git/info/exclude` to keep it off a shared ignore file. Do not edit either file unless asked.

An existing `portfolio/` means tracking is active when this protocol is loaded. At a meaningful work boundary, use update. Do not initialise unrelated projects automatically. This skill does not install a watcher or ensure other agents load it; use the installation instructions to make the protocol discoverable.

## Significance

Include a milestone when evidence supports a change in what people can do, the project's direction, a consequential constraint, or its delivery stage. Ask: **Would this help explain how the project became what it is?**

Signals include a major capability added or removed, an important user flow or interaction, a design direction change, consequential architecture or data-model changes, a major integration, research or testing that changed the solution, accessibility or performance work with a material effect, scope changes, deployment or release, abandoned approaches, and failures that shaped subsequent work.

Group related commits around one outcome or turning point. A milestone can span several days and commits; one commit can contain multiple meaningful changes. Extend an existing milestone when new evidence completes the same development. Record a new entry for a distinct turning point, not merely a new work session.

Normally ignore typos, dependency patches, minor styling, small bug fixes, and refactors without meaningful effect. Their impact can override their category: a small fix restoring an essential accessible interaction may matter. Prefer twelve meaningful events to 150 trivial ones. An update with no new entries is valid.

## Evidence and uncertainty

- Separate observed changes from motivations and outcomes. Code can establish an implementation; it rarely establishes why it was chosen or whether users benefited.
- Use claim-level provenance as short tags after the claim: `[confirmed]` (by the user), `[observed]` (in the repository or a document), `[inferred]`, `[partial]`, or `[unknown: <what is missing>]`. Name the source in the tag when it isn't the repository, e.g. `[observed: audit]` or `[commit claim, unmeasured]`. A user's confirmation of one claim does not confirm the whole entry.
- Cite commit IDs and relevant paths, documentation, or a dated user confirmation. Use short hashes (7+ characters) in the timeline and full IDs in `state.json`. Distinguish stated goals from measured results.
- Do not infer authorship, sole ownership, role, audience, successful deployment, alternatives considered, or user impact solely from code or commit author names. A deployment configuration is not proof of a deployment.
- Preserve uncertainty. If rationale is missing, write `Unknown` and ask only if it would materially improve the later narrative. Never manufacture a compelling reason.
- Inspect relevant local sources only. Do not copy secrets, personal data, or confidential research into history. Refer to a safe source location or a minimal redacted description.

## Contributions and work projects

Capture the user's role and responsibilities in context. Record ownership per milestone in the timeline's Who bullet, separating their work from the team's. Keep supported outcomes and lessons in `context.md`'s Outcomes and Learnings. Include research, facilitation, collaboration, or leadership only when evidence or user confirmation supports those claims. Do not turn tool usage into proof of expertise or imply a formal credential from project participation.

Keep each project's record with that project. When asked to review several projects, use the records the user provides or identifies, retain project attribution, and summarise supported contributions across them. Do not search unrelated workspaces or create a central store automatically.

For work projects, respect the project's rules on confidentiality and storage. Keep internal evidence in its authorised location. Before producing material for an external audience, establish what may be shared and omit or anonymise restricted details. Tracking does not authorise copying employer material into a personal portfolio.

## Init

1. Identify the intended project root and check `portfolio/` before creating anything. If named records exist or the repository holds several distinct projects, work out which project the user means and use `portfolio/<name>/`; confirm the name and scope when they are unclear. If complete, use update. If partial, read and preserve it, reconstruct only missing material, and resolve incompatible formats without overwriting them.
2. Inspect the project before writing files: current structure, README and docs, architecture/design/research notes, TODOs, package changes, and, where available, Git history, meaningful historical diffs, relevant branches and tags. Exclude generated files, dependencies, and Portfolio's own records from candidate milestones. Do not change branches or repository contents to inspect history.
3. Start with an overview, then inspect evidence around likely turning points. Useful Git operations include `git status --short`, `git log --date=iso-strict --format=fuller --stat`, `git show <commit> -- <path>`, and `git diff <base> <tip> -- <paths>`. Commit subjects are leads, not proof. Compare intermediate states when an approach was introduced and later removed, even if the final diff is small.
4. Reconstruct chronological milestones and consequential decisions. Use the current checkout's reachable history as the default scope. Inspect other branches only when useful, label unmerged work, and do not present it as delivered. Note shallow history or other coverage limits.
5. Ask approximately 3–6 high-value questions if necessary, fewer when the evidence is sufficient. Prioritise original problem, audience, personal role, constraints, intended outcome, and unexplained consequential decisions. Consolidate questions; do not conduct a questionnaire. Progress with available evidence and leave unanswered claims unknown.
6. Write the four files using the format reference. Record current uncommitted observations explicitly as provisional, never as historical commits. If there is no Git history, reconstruct only events supported by dated notes, project documents, or user confirmation. Otherwise record a present-day baseline, with no invented chronology.
7. Write state last, after the records are saved. Set the cursor only to the latest commit whose intervening history you actually reviewed. Report meaningful additions and the most important gaps briefly, plus the gitignore note if `portfolio/` is not ignored.

## Update / checkpoint

1. Identify the record to update. With named records, update the one the user names; otherwise update each record whose `scope` the new changes touch, and ignore changes outside every scope. Describe a change shared by several projects in each record's own terms. Read all four files and the current Git status. Validate state before using it. Preserve and diagnose malformed state or an unsupported version; do not silently reset the cursor.
2. Capture the current HEAD as the review tip. If the previous cursor exists and is an ancestor of that tip, inspect the intervening commits and relevant diffs. Also inspect relevant working-tree changes and new user evidence, even if HEAD is unchanged. Exclude `portfolio/` edits themselves.
3. If the cursor is null, missing from Git, or not an ancestor, inspect available history and existing evidence to reconcile a baseline. This may indicate first commits, a shallow clone, a rebase, or a branch switch. Do not assume a simple forward range or erase earlier history. Record the coverage limitation and use a new baseline only after reviewing the relevant available material. With no Git, compare the current project with the recorded baseline; explicitly state that exact change coverage is unavailable.
4. Apply the significance heuristic. Extend, correct, or append entries only when warranted. Deduplicate by meaning and evidence, including provisional entries now committed. Keep decision rationale separate from implementation evidence. Record reversals by linking the earlier decision; preserve what was believed at the time.
5. Update context only for meaningful changes or newly confirmed information. Later corrections should retain a short dated correction note when they alter the story. New user answers may warrant edits without new commits.
6. Save records, then state. Advance the cursor to the captured tip only if its intervening history was reviewed, even when all changes were trivial. Uncommitted work never advances a commit cursor. On a partial review retain the old cursor or the last fully reviewed boundary and record remaining coverage. Preserve `initialised_at`. Recheck state before writing if another agent may be editing; merge their changes rather than overwriting a newer checkpoint.
7. Keep no-op updates quiet: a short acknowledgement is sufficient. Repeating an update without new evidence must not duplicate milestones or decisions.

## Review

Read the records and spot-check important evidence against available sources. With named records, review the one named, or each separately with its attribution. Summarise current context, the user’s contributions, supported outcomes and lessons, major milestones, consequential decisions, inferred or uncertain claims, and a short prioritised list of gaps worth filling. Check for commit-by-commit noise, unsupported rationale or impact, duplicated entries, stale context, coverage limitations, and contradictions.

Review is read-only by default and does not advance the cursor. If asked to repair the history, apply supported corrections using update. Do not turn review into a polished portfolio case study. These files can later supply a separately requested narrative, with uncertainty and attribution preserved.
