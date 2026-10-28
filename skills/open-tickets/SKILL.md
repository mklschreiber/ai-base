---
name: open-tickets
description: Fetch all open issues of this project's Jira project (active sprint and backlog) and show them as tables. Use this when the user asks for open tickets, open tasks, or the current backlog.
---

Fetch all open issues of this project's Jira project. The Jira workflow is described in
"Issue Tracking (Jira)" in `.ai-base/handbook.md`; all project values come from the project
profile `docs/ai-project.md`.

Steps:

1. Read `docs/ai-project.md` → `## Jira`: the **Site**, the **Cloud ID**, the **Project key**
   (`<KEY>` below), **Uses sprints** and the optional **Platform label** (`<LABEL>` below).
   Pass the cloud ID on every Atlassian call.
2. Build the project filter `<SCOPE>`: with a platform label `project = <KEY> AND labels = <LABEL>`,
   without one `project = <KEY>`. Call `searchJiraIssuesUsingJql` (Claude Code:
   `mcp__atlassian__searchJiraIssuesUsingJql`) with `fields: ["summary", "issuetype", "status"]`:
   - If `Uses sprints: yes`, run two queries:
     - **Active sprint:** `<SCOPE> AND statusCategory = "To Do" AND sprint in openSprints() ORDER BY Rank ASC`
     - **Backlog:** `<SCOPE> AND statusCategory = "To Do" AND sprint is EMPTY ORDER BY Rank ASC`
   - If `Uses sprints: no`, run one query:
     `<SCOPE> AND statusCategory = "To Do" ORDER BY Rank ASC`
3. Show the results as tables in rank order — with sprints: active sprint first, then
   backlog; without sprints: one table "Open". Columns: Key, Type, Summary, URL
   (`<Site>/browse/<KEY>`, with the issue key).
4. If nothing is open, report: "No open tickets in the <KEY> project." (with a platform label:
   "No open <LABEL> tickets in the <KEY> project.")
