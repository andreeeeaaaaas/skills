# Skills

Agent skills for Claude Code, Codex and other agents that read `SKILL.md` folders.

| Skill | What it does |
| --- | --- |
| [portfolio](skills/portfolio) | Keeps an evidence-backed record of your projects, contributions, decisions and outcomes in `portfolio/`, ready for case studies, CVs and career discussions. |

## Install

### Claude Code plugin

```
/plugin marketplace add andreeeeaaaaas/skills
/plugin install portfolio@andreeeeaaaaas-skills
```

### skills CLI

```sh
npx skills add andreeeeaaaaas/skills
```

### Manual

Clone the repo and link a skill into your agent's skills folder:

```sh
git clone https://github.com/andreeeeaaaaas/skills.git ~/skills
ln -s ~/skills/skills/portfolio ~/.claude/skills/portfolio
```

### Claude.ai

Zip a skill folder, such as `skills/portfolio`, and upload it under Settings → Capabilities → Skills.

## Licence

[MIT](LICENSE)
