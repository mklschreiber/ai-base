# <Project Name> — Instructions for Claude

This project uses the shared AI workflow from [ai-base](https://github.com/mklschreiber/ai-base),
included as a git submodule in `.ai-base/`. If `.ai-base/` is empty, run
`git submodule update --init` first.

Read before working on this project:

1. [docs/ai-project.md](docs/ai-project.md) — project profile (tech stack, Jira project,
   checks, versioning, project-specific agent rules). It takes precedence over the generic files.
2. [.ai-base/handbook.md](.ai-base/handbook.md) — generic multi-agent workflow (Jira, AI
   Review Gate, review and release).

<Optional project-specific one-liners, e.g. where the application code lives.>

## Agent Definitions (Claude)

`.claude/agents/*.md` are symlinks into [.ai-base/agents/](.ai-base/agents/) (shared with
Copilot). Project rules per agent: `docs/ai-project.md` → `## Agent: <role>`.

| Agent | Definition |
|-------|------------|
| `architect` | [.claude/agents/architect.md](.claude/agents/architect.md) → [.ai-base/agents/architect.md](.ai-base/agents/architect.md) |
| `developer` | [.claude/agents/developer.md](.claude/agents/developer.md) → [.ai-base/agents/developer.md](.ai-base/agents/developer.md) |
| `tester` | [.claude/agents/tester.md](.claude/agents/tester.md) → [.ai-base/agents/tester.md](.ai-base/agents/tester.md) |
| `reviewer` | [.claude/agents/reviewer.md](.claude/agents/reviewer.md) → [.ai-base/agents/reviewer.md](.ai-base/agents/reviewer.md) |

## Skills

`.claude/skills/<name>/SKILL.md` are symlinks into [.ai-base/skills/](.ai-base/skills/)
(shared with Copilot).

| Skill | Definition |
|-------|------------|
| `/open-tickets` | [.claude/skills/open-tickets/SKILL.md](.claude/skills/open-tickets/SKILL.md) → [.ai-base/skills/open-tickets/SKILL.md](.ai-base/skills/open-tickets/SKILL.md) |
| `/implement-next-ticket` | [.claude/skills/implement-next-ticket/SKILL.md](.claude/skills/implement-next-ticket/SKILL.md) → [.ai-base/skills/implement-next-ticket/SKILL.md](.ai-base/skills/implement-next-ticket/SKILL.md) |
| `/resume-current-ticket` | [.claude/skills/resume-current-ticket/SKILL.md](.claude/skills/resume-current-ticket/SKILL.md) → [.ai-base/skills/resume-current-ticket/SKILL.md](.ai-base/skills/resume-current-ticket/SKILL.md) |
| `/tag-releases` | [.claude/skills/tag-releases/SKILL.md](.claude/skills/tag-releases/SKILL.md) → [.ai-base/skills/tag-releases/SKILL.md](.ai-base/skills/tag-releases/SKILL.md) |
