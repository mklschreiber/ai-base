# <Project Name> — AI Project Profile

> Project-specific values for the shared ai-base workflow (`.ai-base/handbook.md`).
> On conflict, this file wins over the generic files.

## Project

<Name and one-line description. Tech stack. Where the code lives. Build/deploy summary.
Stack details: `docs/architecture/stack.md`.>

## Jira

<Hint: the values used by the skills and the handbook on every Atlassian call.>

| Setting | Value |
|---|---|
| Site | `<https://….atlassian.net>` |
| Cloud ID | `<uuid>` |
| Project key | `<KEY>` |
| Board ID | `<n>` |
| Uses sprints | `<yes \| no>` |

| Status | Transition ID |
|---|---|
| Open | `<id>` |
| In Progress | `<id>` |
| In Review | `<id>` |
| Done | `<id>` |

## Branches & Story IDs

Generic rules from the handbook apply.

<Hint: legacy doc naming notes, if any (docs created before the Jira migration).>

## Checks

<Hint: the CI workflows and what they run.>

### Developer runs

<Commands the developer agent runs before handing over.>

### Tester runs

<Commands the tester agent runs (tests, lint, build).>

### Reviewer runs

<Commands the reviewer agent runs if code was changed.>

## Versioning

<File(s) and exact procedure for patch / minor / major.>

### Version source

<Hint: used by /tag-releases to read the version of any commit without a checkout.>

File: `<path relative to the repo root>`

Read command (file content on stdin, prints one `X.Y.Z` line or nothing):

```sh
<command — prefer one without pipes; never Markdown-escape it>
```

## Documentation

<Hint: the sections of `docs/architecture/index.md` to use for concepts, tests and reviews,
and the format of `docs/architecture/log.md`.>

## Important Files

<Hint: project files agents should know about, one bullet each.>

## Agent: architect

<Project rules for the architect (affected layers/units, stack bullet, boundaries), or
"No additional rules.">

## Agent: developer

<Project coding principles, or "No additional rules.">

## Agent: tester

<Test stack, levels and locations, naming convention, test structure example, how to await
asynchronous work, or "No additional rules.">

## Agent: reviewer

<Project rules for the reviewer, or "No additional rules.">
