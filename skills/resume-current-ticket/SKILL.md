---
name: resume-current-ticket
description: Continue the interrupted ticket recorded in the local progress file `.progress.md` (e.g. after a usage limit or an account switch) — load the Jira issue and the recorded state, check out its branch, and carry on with the `/implement-next-ticket` workflow from the recorded step up to the Pull Request. Use this when the user asks to resume, continue or pick up the current or interrupted ticket.
---

Continue the ticket that `/implement-next-ticket` started, from the state recorded in the
hidden, uncommitted file `.progress.md` in the project root (see "Progress File
(`.progress.md`)" in `.ai-base/handbook.md`). The work itself follows the steps of
`.ai-base/skills/implement-next-ticket/SKILL.md` — this skill only restores the context and
picks the step to continue at. All project values come from the project profile
`docs/ai-project.md`. Pass the cloud ID on every Atlassian call.

Steps:

1. **Read the progress file.** If `.progress.md` is missing or empty (only whitespace),
   report: "No ticket in progress (`.progress.md` is empty)." and stop — suggest
   `/implement-next-ticket` for the next ticket. Never guess the ticket from the branch or
   from Jira.
2. **Load context.** Read `docs/ai-project.md` (all sections), `.ai-base/handbook.md` and
   `.ai-base/skills/implement-next-ticket/SKILL.md`. Check the prerequisites: the Atlassian
   MCP server is connected and `gh` is authenticated (`gh auth status`). The working tree
   does **not** have to be clean: it holds the uncommitted work of the ticket. If anything is
   missing, stop and name what is missing.
3. **Load the ticket.** Load the issue named in `.progress.md` with `getJiraIssue` (Claude
   Code: `mcp__atlassian__getJiraIssue`) (summary, type, description, status, comments).
   Compare it with the file: if the Jira status differs from the recorded one, or new
   `Review — Round N` comments exist that are not recorded, tell the user and take the
   Jira state into account when choosing the step below.
4. **Restore the branch.** If the current branch is not the one named in `.progress.md`,
   check it out (with uncommitted changes on another branch, stop and ask the user). Then
   sync the shared AI setup as in step 3 of `/implement-next-ticket`
   (`git submodule update --init .ai-base`, `.ai-base/scripts/link.sh --check`).
5. **Verify the recorded state.** Check the files listed under "Done" and the git state
   (`git status`, `git log <default branch>..HEAD`) against the file. The last recorded
   action may have been cut off: if its result is missing or incomplete (e.g. an agent's
   output file does not exist), treat that action as not done. Update `.progress.md` with
   what you found.
6. **Report and continue.** Tell the user in a few lines which ticket you resume, the step
   you continue at, and the next action. Then continue with that step of
   `/implement-next-ticket` (steps 3–10) and follow it to the end, with the user story, the
   decisions and open points from `.progress.md` as context for every agent you invoke.
   Keep `.progress.md` current exactly as `/implement-next-ticket` requires, and empty it in
   its step 9.2 before committing.
