# Agent Handbook (ai-base)

> This is the **generic** multi-agent workflow shared by all projects that include
> [ai-base](https://github.com/mklschreiber/ai-base) as the git submodule `.ai-base/`.
> Every project-specific value (tech stack, Jira project, checks, versioning, documentation
> sections, project-specific agent rules) lives in the project profile `docs/ai-project.md`.
> **On conflict, the project profile wins over this file.**
>
> Tool-specific instruction files (`CLAUDE.md`, `.github/copilot-instructions.md`) only point
> here and to the profile, and list the agent and skill files that apply to their tool.
> Change workflow content in ai-base, project values in the project profile.

## Multi-Agent System

This workflow uses four specialized agent roles:

| Role | Responsibility |
|-------|---------|
| `architect` | Story concept, architecture decisions, documentation |
| `developer` | Implementation according to the architecture concept |
| `tester` | Testing concept and test implementation |
| `reviewer` | Independent AI review of concept, implementation, and tests before the user reviews |

The concrete agent definition files are located in different places depending on the tool
(see the respective reference file, e.g. `CLAUDE.md` or `.github/copilot-instructions.md`).
All of them are symlinks into `.ai-base/agents/`. Project rules per agent are in profile
`## Agent: <role>`.

## Issue Tracking (Jira)

Stories are tracked in **Jira**. Site, cloud ID, project key, board and transition IDs are
taken from the profile section `## Jira`. Pass the cloud ID on every Atlassian call.

**Workflow statuses** (transition IDs for `transitionJiraIssue` from profile `## Jira`):

| Status | Meaning |
|--------|---------|
| Open | Not started |
| In Progress | Being worked on by the agents |
| In Review | AI review positive, waiting for the user's review / the merge |
| Done | Merged; set by the user only |

Jira shows these names translated when an account uses another language, and the API then
returns the translated name too. Always use the transition IDs from the profile, not names.

In JQL, filter by `statusCategory` (`"To Do"`, `"In Progress"`, `Done`) instead of status
names — status-name filters are unreliable.

**Issue types** drive the branch prefix and the version bump:

| Issue type | Branch prefix | Version bump |
|------------|---------------|--------------|
| `Story` | `feature/` | minor (`1.X.0`) |
| `Bug` | `bug/` | patch (`1.0.X`) |
| `Task` | `task/` | patch (`1.0.X`) |

For any other issue type, ask the user which prefix to use. Labels are not used. A
large/breaking change gets a major bump (`X.0.0`) only after asking the user.

**Story ID:** The Jira issue key (e.g. `<KEY>-39`) is the story ID used everywhere:

- Branch: `<prefix>/<KEY>-<slugified-summary>`, e.g. `bug/<KEY>-39-settings-tooltip-is-never-shown`
- Architecture docs: `docs/architecture/<KEY>-<short-title>.md`, `<KEY>-tests.md`,
  `<KEY>-review.md` (e.g. `<KEY>-39-settings-tooltip.md`)
- Commit messages and PR titles reference the key (e.g. `... (<KEY>-39)`)

Docs created before the Jira migration may use other names: see profile
`## Branches & Story IDs`.

**The issue description is never changed by the agent.**

- **AI review:** recorded only in `docs/architecture/<story-id>-review.md`, not on the Jira
  issue.
- **User review with open points:** added as a **comment** on the issue
  (`addOrEditJiraIssueComment`), one comment per round, headed
  `Review — Round N (<YYYY-MM-DD>)`, then the user's feedback verbatim, followed by an English
  summary (`→ ...`) of what needs to change.

## Typical Workflow for a Story

```
1. User → architect:  "Here is Story <KEY>-42: As a user, I want to..."
2. architect:         Reads docs/architecture/, creates a concept document
3. User → developer:  "Implement Story <KEY>-42 according to the concept"
4. developer:         Reads the concept, implements — if anything is unclear → architect
5. architect:         Answers questions, updates documentation → developer
6. User → tester:     "Write tests for Story <KEY>-42"
7. tester:            Reads concept + code, creates a testing concept and the tests
8. reviewer:          Reads concept + code + tests, performs an independent AI review, and
                       reports a verdict of "positive" or "findings"
9. reviewer:          Records the verdict/findings in
                       docs/architecture/<story-id>-review.md, every round, for
                       traceability (not on the Jira issue)
10a. Findings:        Agent routes the findings back to the responsible agent (architect/
                       developer/tester), then restarts at the reviewer step (8) once
                       addressed
10b. Positive:        Agent moves the issue from "In Progress" to "In Review" and asks
                       the user for their review in the chat
11. User:             Manually verifies the feature/bugfix meets expectations and replies
                       in the chat
12a. Open points:     Agent adds the feedback as a "Review" comment on the issue, moves it
                       back to "In Progress", and the story re-enters this workflow starting
                       at the architect step
12b. Approved:        Agent closes the story (see "Story Review & Release" below)
```

## AI Review Gate

After the tester has created the testing concept and tests, and **before** the issue is
moved to "In Review" and the user is asked for their manual review, the agent invokes
the **reviewer** agent for an independent AI review:

1. **Invoke reviewer.** The reviewer reads the architecture concept, the testing concept, and
   the actual code changes, runs the checks in profile `## Checks → ### Reviewer runs`, and
   documents the round in `docs/architecture/<story-id>-review.md`, ending with a verdict of
   `positive` or `findings`.
2. **Every round is documented in the review file only.** No comment is added to the Jira
   issue for the AI review. Unlike the user review below, the review file records **every**
   round regardless of outcome, for traceability.
3. **Branch on the verdict:**
   - **Findings:** The agent routes the findings to the responsible agent — architect for
     concept gaps, developer for implementation bugs, tester for coverage gaps — has them
     addressed, then re-invokes the reviewer for another round (appending to the same review
     file).
   - **Positive:** The agent proceeds to "Story Review & Release" below.

## Story Review & Release

After the AI review comes back positive, the story does **not** get closed automatically —
it always goes through a manual user review first:

1. **Move to review.** The agent transitions the Jira issue to "In Review"
   (transition ID from profile `## Jira`).
2. **Ask the user.** The agent asks the user, via chat, to manually verify that the
   feature/bugfix meets expectations. Nothing is written to the issue at this point — a
   review is only documented if it turns up open points (see below), so an issue without a
   `Review` comment simply means every round passed.
3. **Branch on the outcome:**
   - **Open points found:** The agent adds a `Review — Round N` comment to the issue with the
     feedback, transitions it back to "In Progress" (transition ID from profile `## Jira`),
     and the story re-enters the normal workflow (architect → developer → tester → review).
   - **Positive review (no findings):** The agent does **not** add a comment — successful
     reviews are not documented. It closes the story:
     1. **Bump the version** as described in profile `## Versioning`, at the level given by
        the issue type (see "Issue Tracking (Jira)"):
        - Bug / Task → patch (`1.0.X`).
        - Story → minor (`1.X.0`), patch reset to `0`.
        - Large/breaking change (ask the user) → major (`X.0.0`), minor and patch reset
          to `0`.
     2. **Commit** the changes with a descriptive commit message that includes the issue key.
        Before committing, apply the `.ai-base` commit guard (see "Shared AI Setup (`.ai-base`)").
     3. **Open a Pull Request** on github.com for the branch, with the issue key in the title.
     4. **Leave the issue in "In Review"** — the agent does not move it to "Done".
        The user moves it manually once the Pull Request is merged.

## Shared AI Setup (`.ai-base`)

The generic agents, skills and this handbook come from the ai-base git submodule in
`.ai-base/`. The project pins an exact ai-base commit. Git does not move the submodule on
`pull`/`checkout` by itself, so:

1. **Sync after every branch switch or pull:** run `git submodule update --init .ai-base`.
   If this moved `.ai-base` to another commit, re-read this handbook and the running
   skill before continuing. Then run `.ai-base/scripts/link.sh --check`. If it fails,
   stop and tell the user: the new ai-base needs link changes, which belong to an ai-base
   update ticket.
2. **Commit guard:** never commit a changed `.ai-base` pointer unless the ticket is a
   deliberate ai-base update (the issue asks to update ai-base or the AI setup, or the
   user explicitly asked for it). Before every commit:
   - Stage with `git add -A` (never use `git commit -a`), then run
     `git diff --cached --quiet -- .ai-base`.
   - Exit code `0` means the pointer is unchanged: commit.
   - Exit code `1` and not an ai-base update ticket: run `git restore --staged .ai-base`,
     then `git submodule update --init .ai-base`, and re-check before committing.
   - Exit code `1` and a deliberate ai-base update: `git -C .ai-base describe --tags --exact-match HEAD`
     must print an `X.Y.Z` tag (otherwise stop: projects pin only ai-base release
     tags). In the commit message and the PR description, name the move as
     `ai-base <old>..<new>`. Each side is the ai-base tag of that commit
     (`git -C .ai-base describe --tags --exact-match <sha>`; the old commit is
     `git rev-parse HEAD:.ai-base`), or its sha7 if it has no tag.
3. **Deliberate update** to ai-base release `<X.Y.Z>`:
   `git -C .ai-base fetch --tags origin && git -C .ai-base checkout --detach <X.Y.Z>`,
   then `.ai-base/scripts/link.sh`, then `.ai-base/scripts/link.sh --check`. Commit
   `.ai-base` together with the changed links. Never use `git submodule update --remote`.
   Read the ai-base release notes for the versions in between. A major version may need
   profile or file changes, which belong to the same ticket.

## Documentation

- **Architecture Concepts:** `docs/architecture/` (OKF format according to `SPEC.md`)
- **Story ID:** the Jira issue key, e.g. `<KEY>-42` (see "Issue Tracking (Jira)")
- **Testing Concepts:** `docs/architecture/<story-id>-tests.md` (created by the `tester` agent)
- **AI Reviews:** `docs/architecture/<story-id>-review.md` (one file per story, one dated round
  per AI Review Gate pass, created/maintained by the `reviewer` agent)
- **Index:** `docs/architecture/index.md` and **Log:** `docs/architecture/log.md` — use the
  sections and the log format named in profile `## Documentation`
- **Tech Stack:** `docs/architecture/stack.md`

## Important Files

- `SPEC.md` — Open Knowledge Format specification (required reading for architect); a
  symlink to `.ai-base/SPEC.md`
- `.ai-base/llm-wiki.md` — Wiki pattern reference
- `docs/ai-project.md` — project profile (all project-specific values); project files are
  listed in its section `## Important Files`

## Skills

- `/open-tickets` — lists the open issues of the project's Jira project (active sprint and
  backlog).
- `/implement-next-ticket` — takes the topmost open issue and runs it through the whole
  workflow above, up to the Pull Request.
- `/tag-releases` — adds missing version tags to the merge commits of the default branch, pushes them, and creates the GitHub releases (asks before pushing).
