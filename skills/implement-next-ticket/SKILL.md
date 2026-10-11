---
name: implement-next-ticket
description: Pick up the topmost open issue from this project's Jira project, move it to "In Progress", implement it end-to-end using the architect, developer, and tester agents, run an independent AI review via the reviewer agent, request the user's manual review, and — once approved — bump the version, commit, and open a Pull Request. Resumes an unfinished ticket from the local, uncommitted `.progress.md` if it exists. Use this when the user asks to implement the next story, continue the current ticket, pick up the next ticket, or work off the top of the backlog.
---

Take the topmost open issue of this project's Jira project, move it to "In Progress", and
implement it through the multi-agent workflow described in `.ai-base/handbook.md`. The
statuses, issue-type mapping and naming conventions are defined in its section "Issue
Tracking (Jira)". All project values (Site, Cloud ID, project key `<KEY>`, transition IDs,
checks, versioning) come from the project profile `docs/ai-project.md`. Pass the cloud ID on
every Atlassian call.

## Progress file (`.progress.md`)

A session can end at any time (usage limit, account switch). So that the next session — on
any account — can continue without losing information, keep the current state of the ticket
in the hidden file `.progress.md` in the project root (see "Progress File (`.progress.md`)"
in `.ai-base/handbook.md`).

- **Never commit it.** Before writing it, run `git check-ignore -q .progress.md`. If that
  exits with a non-zero code, append the line `.progress.md` to `.git/info/exclude` (local
  ignore, no project file changes).
- **Create it** at the end of step 2, as soon as the ticket is known and In Progress.
- **Update it after every step and sub-step below**, after every agent returns, before every
  question to the user, and whenever a decision is made or a user reply arrives. Write it
  *before* moving on, so that the file is never behind the actual state. Overwrite the whole
  file each time (no history log needed beyond what the structure below asks for).
- **Reset it** in step 9.2: delete it (`rm -f .progress.md`) before staging and committing,
  so that it never ends up in the commit or the Pull Request and the next ticket starts
  clean.

Structure (keep these headings; fill in English, concise but complete enough that a fresh
session needs nothing else to continue):

```markdown
# Progress — <KEY>-<n>: <summary>

- Issue: <Site>/browse/<KEY>-<n> (type: <Story|Bug|Task>)
- Branch: <prefix>/<KEY>-<n>-<slug>
- Jira status: <In Progress|In Review>
- Current step: <step number and name of this skill, e.g. "6.3 AI Review Gate — fixing findings">
- Updated: <YYYY-MM-DD HH:MM>

## User story
<the story from step 4>

## Done
- <completed steps, with the files they created/changed, e.g. concept docs/architecture/<KEY>-42-foo.md>

## Next
- <the exact next action(s), including which agent to invoke with what input>

## Open points / decisions
- <open questions, answers from the user or the architect, review findings and their status,
  AI review round count, user review round count>

## Notes
- <anything else a fresh session must know: failed checks and their output summary, workarounds, uncommitted state>
```

Steps:

0. **Load context.** Read `docs/ai-project.md` (all sections) and `.ai-base/handbook.md`.
   **Resume check:** if `.progress.md` exists, read it, check out the branch named there
   (if not already on it), and tell the user which ticket and step you are resuming. Do
   **not** fetch a new ticket and do not require a clean working tree (it holds the
   uncommitted work of that ticket). Check the other prerequisites (Atlassian MCP server,
   `gh auth status`), then continue at the step named under "Current step" / "Next",
   re-verifying the last recorded action (e.g. whether an agent's output files exist)
   before repeating it.
   Otherwise check the prerequisites: the Atlassian MCP server is connected, `gh` is
   authenticated (`gh auth status`), and the working tree is clean. If anything is missing,
   stop and name what is missing.
1. **Fetch the open tickets.** Run the steps of the `open-tickets` skill.
   - If `Uses sprints: yes`: take the topmost issue of the **active sprint** as the ticket to
     work on. If the active sprint has no open issue, show the topmost backlog issue and ask
     the user whether to take it.
   - If `Uses sprints: no`: take the topmost open issue without asking.
   - If nothing is open at all, report: "No open tickets in the <KEY> project." and stop.

   Load the issue with `getJiraIssue` (Claude Code: `mcp__atlassian__getJiraIssue`) (summary,
   type, description).
2. **Move the ticket to "In Progress".** Call `transitionJiraIssue` (Claude Code:
   `mcp__atlassian__transitionJiraIssue`) with the issue key and the ID for In Progress from
   profile `## Jira`. Then create `.progress.md` (see "Progress file" above) with the issue
   and the planned branch name, and keep it up to date from here on.
3. **Create a git branch for the ticket**, in the format `<prefix>/<KEY>-<ticket-name>`:
   - **`<prefix>`** from the issue type: `Story` → `feature`, `Bug` → `bug`, `Task` → `task`.
     For any other type, ask the user which prefix to use instead of guessing.
   - **`<KEY>`**: the Jira issue key, e.g. `<KEY>-42`.
   - **`<ticket-name>`**: the issue summary, slugified — lowercase, non-alphanumeric
     characters replaced with `-`, collapse repeated `-`, trim leading/trailing `-`
     (e.g. "Simulate-Feature" → `simulate-feature`).
   - Combine as `<prefix>/<KEY>-<ticket-name>` (e.g. `feature/<KEY>-42-simulate-feature`).
   - Ensure the working tree is clean, check out the repo's default/main branch, pull the latest
     changes, then create and check out the new branch from it (`git checkout -b <branch-name>`).
   - If a branch with that name already exists locally or remotely, check it out instead of
     creating a new one, and inform the user.
   - **Sync the shared AI setup:** after creating or checking out the branch, run
     `git submodule update --init .ai-base`. If this moved `.ai-base` to another commit,
     re-read `.ai-base/handbook.md` and this skill
     (`.ai-base/skills/implement-next-ticket/SKILL.md`) before continuing. Then run
     `.ai-base/scripts/link.sh --check`. If it fails, stop and tell the user (see
     "Shared AI Setup (`.ai-base`)" in `.ai-base/handbook.md`).
4. **Derive the user story.** Take the issue's summary and description and phrase them as a
   user story ("As a user, I want ... so that ...") if not already in that form. Include the
   issue key and URL (`<Site>/browse/<KEY>` from profile `## Jira`) for traceability. The
   issue key is the **story ID** for all docs (`docs/architecture/<KEY>-*.md`).
5. **Run the agent workflow** as described in `.ai-base/handbook.md`, using the agent
   definitions `.ai-base/agents/architect.md`, `.ai-base/agents/developer.md`, and
   `.ai-base/agents/tester.md`, each extended by profile `## Agent: <role>`:
   1. Invoke the **architect** agent (Claude Code: Agent tool with `subagent_type: architect`)
      with the user story and the issue key to produce/update an architecture concept under
      `docs/architecture/`.
   2. Invoke the **developer** agent (Claude Code: Agent tool with `subagent_type: developer`)
      with the story and a reference to the architecture concept to implement the code. If the
      developer raises an architecture question, route it back to the architect, apply the
      answer, then resume the developer.
   3. Invoke the **tester** agent (Claude Code: Agent tool with `subagent_type: tester`) with
      the story and the implemented code to create the testing concept and tests, then run the
      checks in profile `## Checks → ### Tester runs`.
6. **Run the AI Review Gate** before asking the user, following "AI Review Gate" in
   `.ai-base/handbook.md`, using the agent definition `.ai-base/agents/reviewer.md`
   (extended by profile `## Agent: reviewer`):
   1. Invoke the **reviewer** agent (Claude Code: Agent tool with `subagent_type: reviewer`)
      with the story, the architecture concept, and the implemented code and tests. The
      reviewer documents the round in `docs/architecture/<KEY>-review.md` and reports a verdict
      of `positive` or `findings`.
   2. The review file is the only record of the AI review: do **not** add a Jira comment for
      it, and never edit the issue description. Unlike the user review in step 8, every AI
      review round is recorded there for traceability.
   3. **If the verdict is `findings`:** route each finding to the responsible agent — architect
      for concept gaps, developer for implementation bugs, tester for coverage gaps — have it
      addressed, then repeat this step (re-invoke the reviewer) until the verdict is `positive`.
   4. **If the verdict is `positive`:** continue to step 7.
7. **Move the ticket to "In Review"** and request the user's manual review, following
   "Story Review & Release" in `.ai-base/handbook.md`:
   1. Call `transitionJiraIssue` (Claude Code: `mcp__atlassian__transitionJiraIssue`) with the
      ID for In Review from profile `## Jira`.
   2. Ask the user, in the chat, to manually verify that the feature/bugfix meets
      expectations and to share their review. Do not add a `Review` comment yet — it is only
      written if the user's review turns up open points (see step 8).
8. **Handle the user's review reply:**
   - **If the user reports open points:** Add a comment to the issue via
     `addOrEditJiraIssueComment` (Claude Code: `mcp__atlassian__addOrEditJiraIssueComment`)
     headed `Review — Round N (<YYYY-MM-DD>)`, with the feedback verbatim followed by an
     English summary (`→ ...`) of what needs to change. Move the issue back to "In Progress"
     (the ID for In Progress from profile `## Jira`) and restart the workflow at step 5
     (architect → developer → tester → AI Review Gate → review).
   - **If the user's review is positive (no findings to address):** Do not add a comment —
     successful reviews are not documented. Continue to step 9 to close the story.
9. **Close the story** (only after both a positive AI review and a positive user review):
   1. Bump the version as described in profile `## Versioning`, at the level from the
      handbook's issue-type table: patch (`1.0.X`) for `Bug` and `Task`, minor (`1.X.0`) for
      `Story`. Ask the user if it is a major/breaking change (`X.0.0`).
   2. Reset the progress file: `rm -f .progress.md`. Then stage all changes with
      `git add -A` (never use `git commit -a`) and make sure `.progress.md` is not staged
      (`git diff --cached --name-only -- .progress.md` prints nothing). Then apply the
      `.ai-base` commit guard from "Shared AI Setup (`.ai-base`)" in `.ai-base/handbook.md`:
      run `git diff --cached --quiet -- .ai-base`.
      - Exit code `1` and not a deliberate ai-base update: run
        `git restore --staged .ai-base && git submodule update --init .ai-base`.
      - Exit code `1` and a deliberate ai-base update: check that `.ai-base` is on an ai-base
        release tag, and name `ai-base <old>..<new>` (tags, or sha7 without a tag) in the
        commit message and the PR description, as in the handbook.

      Then commit with a descriptive commit message that includes the issue key.
   3. Push the branch and open a Pull Request on github.com (issue key in the title)
      summarizing the story, the architecture concept, the implementation, the tests, and the
      AI review outcome, with a link to the Jira issue.
   4. Leave the issue in "In Review" — do **not** move it to "Done". The user moves it
      manually once the Pull Request is merged.
   If the session ends after the reset but before the Pull Request exists, the next session
   finds no `.progress.md`: check `gh pr list --head <branch>` and the branch state before
   fetching a new ticket.
10. **Summarize the result** for the user: issue key/title/URL, branch name, architecture
    concept file, changed files, test results, AI review outcome (and review file), user review
    outcome, and — if the story was closed — the new version number, the Pull Request URL, and a
    reminder that the issue is still in "In Review" and should be moved to "Done"
    manually once merged.
