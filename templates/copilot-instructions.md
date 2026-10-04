# <Project Name> — Instructions for GitHub Copilot

This project uses the shared AI workflow from [ai-base](https://github.com/mklschreiber/ai-base),
included as a git submodule in `.ai-base/`. If `.ai-base/` is empty, run
`git submodule update --init` first.

Read before working on this project:

1. [docs/ai-project.md](../docs/ai-project.md) — project profile (tech stack, Jira project,
   checks, versioning, project-specific agent rules). It takes precedence over the generic files.
2. [.ai-base/handbook.md](../.ai-base/handbook.md) — generic multi-agent workflow (Jira, AI
   Review Gate, review and release).

<Optional project-specific one-liners, e.g. where the application code lives.>

## Agent Definitions (Copilot CLI)

`.github/agents/*.agent.md` are symlinks into [.ai-base/agents/](../.ai-base/agents/) (shared
with Claude). Project rules per agent: `docs/ai-project.md` → `## Agent: <role>`.

| Agent | Definition |
|-------|------------|
| `architect` | [.github/agents/architect.agent.md](agents/architect.agent.md) → [.ai-base/agents/architect.md](../.ai-base/agents/architect.md) |
| `developer` | [.github/agents/developer.agent.md](agents/developer.agent.md) → [.ai-base/agents/developer.md](../.ai-base/agents/developer.md) |
| `tester` | [.github/agents/tester.agent.md](agents/tester.agent.md) → [.ai-base/agents/tester.md](../.ai-base/agents/tester.md) |
| `reviewer` | [.github/agents/reviewer.agent.md](agents/reviewer.agent.md) → [.ai-base/agents/reviewer.md](../.ai-base/agents/reviewer.md) |

## Skills

`.github/skills/<name>/SKILL.md` are symlinks into [.ai-base/skills/](../.ai-base/skills/)
(shared with Claude).

| Skill | Definition |
|-------|------------|
| `open-tickets` | [.github/skills/open-tickets/SKILL.md](skills/open-tickets/SKILL.md) → [.ai-base/skills/open-tickets/SKILL.md](../.ai-base/skills/open-tickets/SKILL.md) |
| `implement-next-ticket` | [.github/skills/implement-next-ticket/SKILL.md](skills/implement-next-ticket/SKILL.md) → [.ai-base/skills/implement-next-ticket/SKILL.md](../.ai-base/skills/implement-next-ticket/SKILL.md) |
| `tag-releases` | [.github/skills/tag-releases/SKILL.md](skills/tag-releases/SKILL.md) → [.ai-base/skills/tag-releases/SKILL.md](../.ai-base/skills/tag-releases/SKILL.md) |
