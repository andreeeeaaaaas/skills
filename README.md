# Skills

Skills I've created for Claude Code, Codex and other agents that read `SKILL.md` folders.

## Available skills

### [/portfolio](skills/portfolio)
Record contributions, decisions, and key context over time across personal and work projects.

### [/tmpmd](skills/tmpmd)
Open your agent's last answer as a temporary Markdown note, or keep one updating as you work.

## Install

Choose the method your AI supports. If you're unsure which to use, copy [this repository’s URL](https://github.com/andreeeeaaaaas/skills) and ask your agent to install the skills.

### Skills CLI

For compatible agents:

```sh
npx skills add andreeeeaaaaas/skills
```

### AI chats and projects

Upload the skill’s `SKILL.md` and any referenced files. For `/portfolio`, include `references/format.md`. `/tmpmd` needs an agent that can run shell commands.

### Claude Code plugin

```text
/plugin marketplace add andreeeeaaaaas/skills
/plugin install portfolio@andreeeeaaaaas-skills
/plugin install tmpmd@andreeeeaaaaas-skills
```

`/tmpmd on` also needs a hook in your settings. See [continuous mode setup](skills/tmpmd/README.md#continuous-mode-setup).

### Manual installation

Download this repository and copy the complete skill folder, such as `skills/portfolio/`, into your agent’s skills directory. Check your agent’s documentation for its location.

## Licence

[MIT](LICENSE)
