---
name: tag-releases
description: Find merge commits on the default branch whose version has no git tag yet, create and push the missing version tags, and create the matching GitHub releases. Shows the plan and asks before pushing. Use this when the user asks to tag releases, add missing tags, or create missing GitHub releases. Say "dry-run" to only see the plan.
---

Add the missing version tags to the merge commits of the default branch, push them, and
create the matching GitHub releases. Everything project-specific (the file that holds the
version and how to read it) comes from the project profile `docs/ai-project.md`. The working
tree and the current branch are never touched, so this is safe to run on any branch with
uncommitted work.

Write all shell variables braced (`"${sha}:${file}"`): in zsh, `$sha:a…` triggers a path
modifier.

Steps:

1. **Load the version source.** Read `docs/ai-project.md` → `## Versioning` →
   `### Version source`:
   - `file` = the path between the backticks on the line starting with `File:`.
   - `<Read command>` = the content of the only fenced `sh` code block in that subsection,
     used verbatim. Do not add, remove or unescape any character.

   If the subsection, the `File:` line or the code block is missing, stop with "No
   `### Version source` in docs/ai-project.md". Self-check: run
   `git show "HEAD:${file}" | <Read command>`. If it does not print one `X.Y.Z` line, stop
   with "Read command in docs/ai-project.md does not return a version for HEAD" and show
   the output. If the user said "dry-run", set the dry-run flag.
2. **Prerequisites.** `gh auth status` must exit 0. Get the default branch:
   `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` (`<default>` below). If
   either fails, stop and name what is missing.
3. **Fetch.** Run `LC_ALL=C git fetch origin "<default>" --tags`. Do not prune and do not
   check out anything. Do not parse its output: decide only by the exit code. If it exits
   non-zero:
   - Show git's error output as it is.
   - Find the conflicting tags by comparing refs (locale-independent). For every line
     `<oid>\trefs/tags/<tag>` of `git ls-remote --tags --refs origin`:
     - local = `git rev-parse -q --verify "refs/tags/<tag>"`
     - if local exists and differs from `<oid>`: list `<tag>` with
       local `git rev-parse --short "refs/tags/<tag>^{}"` and the remote `<oid>` (short).
   - Stop with "Tag conflict between local and origin — resolve manually; nothing was
     changed." If no conflicting tag was found, stop with "Fetch failed — see the git
     error above; nothing was changed."

   Never retry with `--force`, and never delete or move a tag. Do not parse human-readable
   git or gh messages anywhere in this skill: use exit codes, plumbing output or
   `--format`/`--json`.
4. **Existing tags.**
   - Remote: `git ls-remote --tags --refs origin | sed 's#.*refs/tags/##'`.
   - Local: `git tag --list`.
   - The tag format is plain `X.Y.Z`. A version `X.Y.Z` counts as tagged if `X.Y.Z` or
     `vX.Y.Z` is in either list. Every `vX.Y.Z` tag is added to "Warnings" as
     "`<tag>`: non-standard tag format, ignored for releases and Latest". It gets no
     release-only entry and is not considered for Latest (step 6). A
     local-only tag is still "tagged", but list it under "Warnings" ("local tag not on
     origin; push it manually if it is correct"). The skill never pushes tags it did not
     create in this run.
5. **Scan.** For each `sha` in
   `git rev-list --first-parent --merges --reverse "origin/<default>"` (oldest first):
   - `version=$(git show "${sha}:${file}" 2>/dev/null | <Read command>)`
   - If the version is empty or does not match `^[0-9]+\.[0-9]+\.[0-9]+$`: add the warning
     `<sha7>: no readable version` and continue.
   - If the version is `0.0.0`: add the note `<sha7>: placeholder 0.0.0 skipped` and
     continue.
   - Otherwise remember only the **last** `sha` for each version: a later merge with the
     same version replaces the earlier one. The tag goes on the newest merge that still
     carries the version, so it contains every change merged before the next version bump.
     A version that is already tagged (step 4) keeps its tag, even if later merges carry
     the same version: the skill never moves a tag.
6. **Plan.**
   - **New tags:** every remembered version that is not tagged (step 4), with:
     - its `sha7`;
     - the merge date (`git log -1 --format=%cs "${sha}"`);
     - the PR title: the first non-empty line of the body,
       `git log -1 --format=%b "${sha}" | sed -n '/./{p;q;}'`, with the subject
       (`%s`, e.g. "Merge pull request #24 from …") as the fallback.
   - **Release only:** every existing remote tag that matches `^[0-9]+\.[0-9]+\.[0-9]+$`
     and has no release. Check with `gh release view "<tag>" >/dev/null 2>&1`; a non-zero
     exit code means no release.
   - **Latest:** compute the highest semver among all plain `X.Y.Z` tags after the run
     (existing plus new; compare numerically per field; `v` tags are excluded). Only the
     release for that version gets `--latest`, and only if it is created in this run. If any
     `vX.Y.Z` tag is higher than that version, add the warning "`<tag>` is higher than the
     computed Latest `<version>` — Latest may be wrong, check manually".
   - Show one table sorted ascending by semver, with columns Version, Commit, Date, PR title,
     and Action (`tag + push + release` | `release only`). Below it, list the skipped and
     existing versions, the warnings and the notes, and which version will be "Latest".
   - If both lists are empty, report "All versions are tagged and released." and stop.
7. **Confirm.** If dry-run: stop after the plan ("Dry run — nothing changed."). Otherwise
   ask the user to confirm the plan exactly as shown. Without a clear yes, stop without
   changes.
8. **Execute**, ascending by semver, one version at a time:
   1. For a new tag:
      - `git tag "<version>" "<sha>"` (lightweight, no `v` prefix)
      - `git push origin "refs/tags/<version>"`

      If the push fails, delete the local tag again (`git tag -d "<version>"`), report it,
      and continue with the next version. Do not create a release for it.
   2. Release: `gh release create "<version>" --verify-tag --title "<version>"
      --generate-notes` plus `--latest` for the Latest version and `--latest=false` for all
      others. If it fails, report it and continue.
9. **Report:** a table of created tags and releases (URL per release:
   `gh release view "<version>" --json url --jq .url`), the skipped versions with their reason, the warnings, the failures, and the
   current "Latest". Re-running the skill is safe: anything already done is skipped by steps
   4 and 6.
