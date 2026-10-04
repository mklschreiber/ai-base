---
name: open-tickets
description: Fetch all open issues of this project's Jira project (active sprint and backlog) and show them as tables. Use this when the user asks for open tickets, open tasks, or the current backlog.
---

Fetch all open issues of this project's Jira project. The Jira workflow is described in
"Issue Tracking (Jira)" in `.ai-base/handbook.md`; all project values come from the project
profile `docs/ai-project.md`.

Steps:

1. Read `docs/ai-project.md` → `## Jira`: the **Site**, the **Cloud ID**, the **Project key**
   (`<KEY>` below) and **Uses sprints**. Pass the cloud ID on every Atlassian call.
2. Call `searchJiraIssuesUsingJql` (Claude Code: `mcp__atlassian__searchJiraIssuesUsingJql`)
   with `fields: ["summary", "issuetype", "status"]`:
   - If `Uses sprints: yes`, run two queries:
     - **Active sprint:** `project = <KEY> AND statusCategory = "To Do" AND sprint in openSprints() ORDER BY Rank ASC`
     - **Backlog:** `project = <KEY> AND statusCategory = "To Do" AND sprint is EMPTY ORDER BY Rank ASC`
   - If `Uses sprints: no`, run one query:
     `project = <KEY> AND statusCategory = "To Do" ORDER BY Rank ASC`
3. Show the results as tables in rank order — with sprints: active sprint first, then
   backlog; without sprints: one table "Open". Columns: Key, Type, Summary, URL
   (`<Site>/browse/<KEY>`, with the issue key).
4. If nothing is open, report: "No open tickets in the <KEY> project."
