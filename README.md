# ai-base

The generic AI workflow for my projects, for **Claude Code** and **GitHub Copilot**: agent
definitions (architect, developer, tester, reviewer), the agent handbook, skills, the Open
Knowledge Format spec, and templates. Projects include this repository as the git submodule
`.ai-base/` and link the generic files with symlinks, so an improvement is made once here and
picked up by every project.

The AI configuration of a project has three layers:

1. **ai-base (generic, shared):** agents, handbook, skills, `SPEC.md`, templates, link script.
   Contains no project names, Jira keys, commands or project paths.
2. **Project profile `docs/ai-project.md` (per project, real file):** every project-specific
   value the generic files need (tech stack, Jira project, checks, versioning, documentation
   format, project rules per agent), under fixed headings. **The profile wins over the
   generic files on conflict.**
3. **Tool entry files (per project, real files):** `CLAUDE.md`,
   `.github/copilot-instructions.md`, `.mcp.json`. They only point to 1 and 2 and list the
   agents and skills.

## Contents

```
ai-base/
├── README.md                     this integration guide
├── LICENSE                       MIT
├── handbook.md                   generic agent handbook (Jira workflow, AI Review Gate, release)
├── SPEC.md                       Open Knowledge Format spec
├── llm-wiki.md                   wiki pattern reference
├── agents/
│   ├── architect.md
│   ├── developer.md
│   ├── tester.md
│   └── reviewer.md
├── skills/
│   ├── open-tickets/SKILL.md
│   ├── implement-next-ticket/SKILL.md
│   ├── resume-current-ticket/SKILL.md
│   └── tag-releases/SKILL.md
├── scripts/
│   └── link.sh                   creates and checks the project symlinks
├── tests/
│   ├── link.test.sh              tests for scripts/link.sh
│   └── tag-releases.test.sh      tests for the commands of skills/tag-releases
└── templates/
    ├── ai-project.md             profile template with all required headings
    ├── CLAUDE.md
    ├── copilot-instructions.md
    └── mcp.json
```

## Add ai-base to a project

Run from the project root:

```sh
git submodule add ../ai-base.git .ai-base
git -C .ai-base checkout --detach <X.Y.Z>   # the latest ai-base release
.ai-base/scripts/link.sh
```

The relative URL resolves against the project's `origin`, so SSH and HTTPS clones both work.
`link.sh` never overwrites a regular file, so remove an existing regular `SPEC.md` first
(`git rm SPEC.md`) if it is the same spec.

Then copy the templates and fill in the profile:

| Template | Copy to |
|---|---|
| `templates/CLAUDE.md` | `CLAUDE.md` |
| `templates/copilot-instructions.md` | `.github/copilot-instructions.md` |
| `templates/mcp.json` | `.mcp.json` |
| `templates/ai-project.md` | `docs/ai-project.md` |

Commit `.gitmodules`, `.ai-base`, the symlinks and the copied files.

## Clone a project

```sh
git clone --recurse-submodules <url>
```

In an existing clone: `git submodule update --init`. Optional per-user setting, so that
`git pull`/`git checkout` keep the submodule in sync:

```sh
git config submodule.recurse true
```

## Update a project to a newer ai-base release

```sh
git -C .ai-base fetch --tags origin && git -C .ai-base checkout --detach <X.Y.Z>
.ai-base/scripts/link.sh
.ai-base/scripts/link.sh --check
```

Commit `.ai-base` (plus any changed links) as `ai-base <old>..<new>`. List the available
releases with `git -C .ai-base tag --list --sort=-v:refname`. Read the release notes in
between, especially before a major update.

`link.sh` prints `linked:`, `override:` and `removed stale:` lines. `link.sh --check` prints
`MISSING`, `WRONG`, `BROKEN` or `STALE` lines for every problem and exits with `1` if there
is one, `0` otherwise.

## Tests

Run after every change to `scripts/link.sh` or to the commands in
`skills/tag-releases/SKILL.md`:

```sh
tests/link.test.sh
tests/tag-releases.test.sh
```

They need only bash (3.2 or newer) and git, and build throwaway projects and repositories in
the temp directory. `tag-releases.test.sh` mirrors the skill's git commands, checks that they
still appear verbatim in `SKILL.md`, pushes only to a throwaway bare repository and uses a
`gh` stub (it never contacts GitHub). Each script prints one line per test and exits with `1`
if a test fails.

## Pinning

Projects pin only ai-base release tags and stay on them until someone runs the update above
and commits the new pointer. An ai-base change can therefore never break a project silently.
`.gitmodules` has no `branch =` entry, and `git submodule update --remote` is not used.

## Releasing ai-base

ai-base is versioned with plain semver tags `X.Y.Z` (no `v` prefix), and each tag has a
GitHub release. Projects pin only these tags.

After merging a pull request into `main` (with "Create a merge commit"):

```sh
git checkout main && git pull --ff-only
git tag <X.Y.Z> HEAD
git push origin refs/tags/<X.Y.Z>
gh release create <X.Y.Z> --verify-tag --title <X.Y.Z> --generate-notes
```

Choose the version from the previous tag (`git tag --list --sort=-v:refname | head -n 1`):

| Bump | When |
|---|---|
| patch | wording fixes, bug fixes |
| minor | a new skill or agent, other backward-compatible additions |
| major | breaking changes to the profile schema (`templates/ai-project.md`) or the link layout (`scripts/link.sh`), so that projects must change files when they update |

Never move or recreate an existing tag. `/tag-releases` does not apply to ai-base (no
version file and no profile).

## Progress file

`/implement-next-ticket` keeps the state of the running ticket in `.progress.md` in the
project root and empties it before the story's commit and Pull Request. If a session is
interrupted (usage limit, account switch), the user continues the ticket with
`/resume-current-ticket`. `/implement-next-ticket` never resumes on its own: if the file is
not empty, it asks the user what to do. The file is local only: the skills add it to
`.git/info/exclude` if it is not ignored yet. Projects may also add `.progress.md` to their
`.gitignore`. Structure and rules: handbook section "Progress File (`.progress.md`)".

## Extend or override

- **Extend (default):** put the project rules for a role into the profile section
  `## Agent: <role>`.
- **Replace (rare):** delete the project's symlinks for that agent and commit a real file with
  the same name in `.claude/agents/<role>.md` (and `.github/agents/<role>.agent.md`).
  `link.sh` never overwrites a regular file and reports it as `override`.
- **Project-only agents or skills:** a real file `.claude/agents/<name>.md` or a real
  directory `.claude/skills/<name>/` (plus the `.github/` counterpart). `link.sh` ignores
  anything that does not point into `.ai-base/`.

## Profile schema

`docs/ai-project.md` must contain these headings, in this order (see
`templates/ai-project.md`):

```
# <Project Name> — AI Project Profile
## Project
## Jira                 (Site, Cloud ID, Project key, Board ID, Uses sprints, transition IDs)
## Branches & Story IDs
## Checks
### Developer runs
### Tester runs
### Reviewer runs
## Versioning
### Version source  (`File:` line + one fenced `sh` read command; used by /tag-releases)
## Documentation
## Important Files
## Agent: architect
## Agent: developer
## Agent: tester
## Agent: reviewer
```

The generic files refer to these sections by heading name. A generic change that needs a new
profile section must update `templates/ai-project.md` and say so in the PR description.

## Supported tools and runtimes

- **Claude Code (local):** agents from `.claude/agents/`, skills from
  `.claude/skills/<name>/SKILL.md` (available as `/open-tickets`,
  `/implement-next-ticket`, `/resume-current-ticket` and `/tag-releases`), MCP servers from
  `.mcp.json`.
- **GitHub Copilot CLI / IDE (local):** agents from `.github/agents/<role>.agent.md`, skills
  from `.github/skills/<name>/SKILL.md`, always-loaded instructions from
  `.github/copilot-instructions.md`.
- `.github/copilot-instructions.md` stays a real file, because GitHub reads it server side
  where the submodule is not checked out.
- The cloud Copilot coding agent is not a supported runtime (it may not initialize
  submodules).
- Symlinks require macOS/Linux, or Windows with `core.symlinks=true`.

## Consumers

- [myStandby](https://github.com/mklschreiber/myStandby)
- [myStandby-LandingPage](https://github.com/mklschreiber/myStandby-LandingPage)
- [michaelschreibernet](https://github.com/mklschreiber/michaelschreibernet)
