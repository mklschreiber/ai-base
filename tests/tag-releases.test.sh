#!/usr/bin/env bash
# Tests for the commands of skills/tag-releases/SKILL.md.
#
# Usage: tests/tag-releases.test.sh     (from the ai-base root or anywhere else)
#
# Testing concept:
# - The skill is prose for an agent, but its git commands are deterministic. This
#   suite MIRRORS them (it does not parse them out of the prose): `skill_plan` and
#   `skill_execute` below run steps 1-6 and 8 with exactly the commands and
#   messages that SKILL.md documents, with the placeholders filled in. Step 1
#   parses a real profile file (`File:` line + the only fenced `sh` block of
#   `### Version source`) and runs the block verbatim with `bash -c`. The drift tests at the
#   top assert that every mirrored command still appears verbatim in SKILL.md,
#   so a change to the skill's commands makes this suite fail until it is mirrored.
# - Fixture: a throwaway bare repo "origin.git" and a clone "work" in a temp
#   dir. `main` has first-parent merge commits with a version in
#   app/package.json (read with the web profiles' read command from a fixture
#   docs/ai-project.md), covering: missing version file, 0.0.0 placeholder, a
#   version shared by two merges, an existing remote tag without a release,
#   an existing tag on an EARLIER merge of the same version, an unparsable
#   version, a local-only v-prefixed tag (non-standard format), a merge reached only via a second
#   parent (must be ignored) and a new newest version.
# - `gh` is a stub on PATH: `release view` answers from a state file,
#   `release create` appends its arguments to that file. GitHub is never
#   called. Tags are pushed only to the throwaway bare origin.
# - Not covered: the agent's dialogue (confirmation, table rendering), real
#   GitHub release creation, `gh auth status`/`gh repo view` against GitHub.
# - Needs only bash 3.2+, git and coreutils. No network.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$ROOT/skills/tag-releases/SKILL.md"

# Version source written into the fixture profile (same read command as the
# web profiles). The skill under test reads both back from docs/ai-project.md.
FIXTURE_FILE="app/package.json"
FIXTURE_READ_CMD="awk -F'\"' '/^  \"version\":/{print \$4; exit}'"

# Messages the mirror prints; the drift test pins them against SKILL.md.
MSG_NO_SOURCE='No `### Version source` in docs/ai-project.md'
MSG_SELF_CHECK='Read command in docs/ai-project.md does not return a version for HEAD'
MSG_CONFLICT='Tag conflict between local and origin — resolve manually; nothing was changed.'
MSG_FETCH_FAILED='Fetch failed — see the git error above; nothing was changed.'
MSG_V_FORMAT='non-standard tag format, ignored for releases and Latest'
MSG_LOCAL_ONLY='local tag not on origin; push it manually if it is correct'

passed=0
failed=0
failures=""
test_failed=0

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

fail() {
  test_failed=1
  echo "    FAIL: $*"
}

assert_eq() { # expected actual message
  [ "$1" = "$2" ] || fail "$3: expected [$1], got [$2]"
}

assert_contains() { # haystack needle message
  case "$1" in
    *"$2"*) ;;
    *) fail "$3: [$2] not in [$1]" ;;
  esac
}

assert_not_contains() { # haystack needle message
  case "$1" in
    *"$2"*) fail "$3: unexpected [$2] in [$1]" ;;
    *) ;;
  esac
}

# SKILL.md with line breaks and indentation folded to single spaces, so that
# snippets that wrap in the Markdown source can be matched.
skill_flat() { tr '\n' ' ' < "$SKILL_MD" | tr -s ' '; }

assert_skill_has() { # literal snippet
  skill_flat | grep -qF -- "$1" || fail "SKILL.md no longer contains: $1"
}

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

TEMPLATE=""

commit_version() { # version|-|missing  message
  if [ "$1" = "missing" ]; then
    rm -f "$FIXTURE_FILE"
  else
    mkdir -p app
    printf '{\n  "name": "fixture",\n  "version": "%s",\n  "private": true\n}\n' "$1" > "$FIXTURE_FILE"
  fi
  git add -A >/dev/null
  git commit -q --allow-empty -m "$2"
}

# Merges a feature branch into main with a GitHub-style merge message.
# Args: number  version  pr-title
merge_pr() {
  git checkout -q -b "feature/$1" main
  commit_version "$2" "change for #$1"
  git checkout -q main
  git merge -q --no-ff "feature/$1" -m "Merge pull request #$1 from me/feature/$1" -m "$3"
  git branch -q -D "feature/$1"
}

sha_of_merge() { # pr-number → full sha of that merge on main
  git -C "$WORK" log --first-parent --merges --format='%H %s' main | awk -v n="#$1" '$5==n{print $1}'
}

# Builds the fixture once; each test copies it.
build_template() {
  TEMPLATE="$(mktemp -d "${TMPDIR:-/tmp}/tag-releases-test.XXXXXX")"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
  export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  export GIT_AUTHOR_DATE="2026-01-01T12:00:00Z" GIT_COMMITTER_DATE="2026-01-01T12:00:00Z"
  git init -q --bare -b main "$TEMPLATE/origin.git"
  git init -q -b main "$TEMPLATE/seed"
  cd "$TEMPLATE/seed" || exit 1
  commit_version missing "initial"
  merge_pr 1 missing "PR 1 without version file"
  merge_pr 2 0.0.0 "PR 2 scaffold"
  export GIT_COMMITTER_DATE="2026-02-03T12:00:00Z"
  merge_pr 3 1.0.0 "PR 3 first 1.0.0"
  merge_pr 4 1.0.0 "PR 4 last 1.0.0"
  merge_pr 5 1.1.0 "PR 5 tagged without release"
  merge_pr 6 1.2.0 "PR 6 tagged 1.2.0 earlier"
  merge_pr 7 1.2.0 "PR 7 last 1.2.0"
  merge_pr 8 1.3 "PR 8 unparsable"
  merge_pr 9 1.3.0 "PR 9 has local v-tag"
  # A merge commit that is only reachable through a second parent: a helper
  # branch (other file only) is merged into a feature branch that carries
  # 9.9.9, then the feature branch is merged into main with a later version.
  # 9.9.9 must never be planned.
  git checkout -q -b feature/side main
  commit_version 9.9.9 "side version"
  git checkout -q -b feature/helper main
  echo helper > helper.txt
  git add helper.txt
  git commit -q -m "helper"
  git checkout -q feature/side
  git merge -q --no-ff feature/helper -m "Merge branch feature/helper into feature/side"
  git branch -q -D feature/helper
  commit_version 2.0.0 "side final version"
  git checkout -q main
  export GIT_COMMITTER_DATE="2026-03-04T12:00:00Z"
  git merge -q --no-ff feature/side -m "Merge pull request #10 from me/feature/side" -m "PR 10 newest"
  git branch -q -D feature/side
  git remote add origin "$TEMPLATE/origin.git"
  git push -q origin main
  # Existing remote tags: 1.1.0 (no release), 1.2.0 on the EARLIER merge (with release).
  git tag 1.1.0 "$(git log --first-parent --merges --format='%H %s' main | awk '$5=="#5"{print $1}')"
  git tag 1.2.0 "$(git log --first-parent --merges --format='%H %s' main | awk '$5=="#6"{print $1}')"
  git push -q origin refs/tags/1.1.0 refs/tags/1.2.0
  git clone -q "$TEMPLATE/origin.git" "$TEMPLATE/work"
  # Local-only tag in the clone (never pushed).
  git -C "$TEMPLATE/work" tag v1.3.0 "$(git log --first-parent --merges --format='%H %s' main | awk '$5=="#9"{print $1}')"
  # gh stub: state file lists tags that have a release.
  mkdir -p "$TEMPLATE/bin"
  cat > "$TEMPLATE/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub for the gh calls of the tag-releases skill. Never contacts GitHub.
case "$1 $2" in
  "auth status") exit 0 ;;
  "repo view") echo main ;;
  "release view")
    grep -qx "$3" "$GH_RELEASES" || exit 1
    [ "${4:-}" = "--json" ] && [ "$5 $6 $7" = "url --jq .url" ] && echo "https://github.invalid/releases/tag/$3"
    exit 0
    ;;
  "release create")
    shift 2
    echo "$*" >> "$GH_CREATE_LOG"
    echo "$1" >> "$GH_RELEASES"
    echo "https://github.invalid/releases/tag/$1"
    ;;
  *) echo "gh stub: unexpected call: $*" >&2; exit 99 ;;
esac
STUB
  chmod +x "$TEMPLATE/bin/gh"
  echo "1.2.0" > "$TEMPLATE/releases"
  : > "$TEMPLATE/create.log"
  cd / || exit 1
}

# Writes docs/ai-project.md in the work tree in the template layout.
# Args: file-line (full line or empty to omit)  sh-block-content (or empty to
# omit the block)  [heading, default "### Version source"]
write_profile() {
  mkdir -p docs
  {
    echo "# Fixture — AI Project Profile"
    echo
    echo "## Versioning"
    echo
    echo "Bump app/package.json."
    echo
    echo "${3:-### Version source}"
    echo
    [ -n "$1" ] && { echo "$1"; echo; }
    echo 'Read command (file content on stdin, prints one `X.Y.Z` line or nothing):'
    echo
    [ -n "$2" ] && { echo '```sh'; echo "$2"; echo '```'; echo; }
    echo "## Documentation"
    echo
    echo "File: \`wrong/file.json\` (must not be picked up, other section)"
    echo
    echo '```sh'
    echo 'echo 6.6.6'
    echo '```'
  } > docs/ai-project.md
}

make_fixture() {
  BASE="$(mktemp -d "${TMPDIR:-/tmp}/tag-releases case.XXXXXX")"
  cp -R "$TEMPLATE/." "$BASE/"
  # The clone's origin URL points at the template; re-point it to the copy.
  git -C "$BASE/work" remote set-url origin "$BASE/origin.git"
  WORK="$BASE/work"
  export GH_RELEASES="$BASE/releases" GH_CREATE_LOG="$BASE/create.log"
  export PATH="$BASE/bin:$PATH"
  cd "$WORK" || exit 1
  write_profile "File: \`${FIXTURE_FILE}\`" "${FIXTURE_READ_CMD}"
}

# ---------------------------------------------------------------------------
# Mirror of SKILL.md steps 2-6 and 8 (commands verbatim, placeholders filled)
# ---------------------------------------------------------------------------

is_semver() { printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; }

semver_sort() { sort -t. -k1,1n -k2,2n -k3,3n; }

# Step 1: sets FILE and READ_CMD from docs/ai-project.md, or prints
# "STOP: <message>" and returns 1.
skill_load_source() {
  local section out
  section="$(awk '/^### Version source$/{f=1;next} f&&/^##/{exit} f' docs/ai-project.md 2>/dev/null)"
  FILE="$(printf '%s\n' "${section}" | sed -n 's/^File: `\([^`]*\)`.*/\1/p' | head -n 1)"
  READ_CMD="$(printf '%s\n' "${section}" | awk '/^```sh$/{f=1;next} /^```$/{if(f)exit} f')"
  if ! printf '%s\n' "${section}" | grep -q . || [ -z "${FILE}" ] || [ -z "${READ_CMD}" ]; then
    echo "STOP: ${MSG_NO_SOURCE}"
    return 1
  fi
  # Self-check: git show "HEAD:${file}" | <Read command>
  out="$(git show "HEAD:${FILE}" 2>&1 | bash -c "${READ_CMD}" 2>&1)"
  if [ "$(printf '%s\n' "${out}" | wc -l | tr -d ' ')" != 1 ] || ! is_semver "${out}"; then
    echo "STOP: ${MSG_SELF_CHECK}"
    echo "output: ${out}"
    return 1
  fi
}

# Writes the plan into $BASE/plan/: new (version sha), release_only (tag),
# warnings, notes, latest. Prints "All versions are tagged and released." if
# there is nothing to do, or "STOP: <message>" (return 1) where the skill stops.
skill_plan() {
  local default sha version v line fetch_out tag
  P="$BASE/plan"
  rm -rf "$P"; mkdir -p "$P"
  : > "$P/warnings"; : > "$P/notes"; : > "$P/last"; : > "$P/new"; : > "$P/release_only"
  # Step 1
  skill_load_source || return 1
  # Step 2
  gh auth status >/dev/null || return 1
  default="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
  # Step 3
  # Decided by the exit code only; the output is shown, never parsed.
  if ! fetch_out="$(LC_ALL=C git fetch origin "${default}" --tags 2>&1)"; then
    echo "${fetch_out}"
    : > "$P/conflicts"
    git ls-remote --tags --refs origin 2>/dev/null | while IFS="$(printf '\t')" read -r oid ref; do
      tag="${ref#refs/tags/}"
      local_oid="$(git rev-parse -q --verify "refs/tags/${tag}")" || continue
      [ "${local_oid}" = "${oid}" ] && continue
      echo "conflict: ${tag} local $(git rev-parse --short "refs/tags/${tag}^{}") remote ${oid:0:7}" >> "$P/conflicts"
    done
    cat "$P/conflicts"
    if [ -s "$P/conflicts" ]; then
      echo "STOP: ${MSG_CONFLICT}"
    else
      echo "STOP: ${MSG_FETCH_FAILED}"
    fi
    return 1
  fi
  # Step 4
  git ls-remote --tags --refs origin | sed 's#.*refs/tags/##' > "$P/remote_tags"
  git tag --list > "$P/local_tags"
  grep -hE '^v[0-9]+\.[0-9]+\.[0-9]+$' "$P/remote_tags" "$P/local_tags" | sort -u > "$P/v_tags"
  while read -r tag; do
    echo "\`${tag}\`: ${MSG_V_FORMAT}" >> "$P/warnings"
  done < "$P/v_tags"
  while read -r tag; do
    grep -qxF "${tag}" "$P/remote_tags" || echo "\`${tag}\`: ${MSG_LOCAL_ONLY}" >> "$P/warnings"
  done < "$P/local_tags"
  # Step 5
  for sha in $(git rev-list --first-parent --merges --reverse "origin/${default}"); do
    version=$(git show "${sha}:${FILE}" 2>/dev/null | bash -c "${READ_CMD}")
    if [ -z "${version}" ] || ! is_semver "${version}"; then
      echo "${sha:0:7}: no readable version" >> "$P/warnings"
      continue
    fi
    if [ "${version}" = "0.0.0" ]; then
      echo "${sha:0:7}: placeholder 0.0.0 skipped" >> "$P/notes"
      continue
    fi
    # Keep only the last sha per version: drop an earlier entry, then append.
    grep -v "^${version} " "$P/last" > "$P/last.tmp"
    mv "$P/last.tmp" "$P/last"
    echo "${version} ${sha}" >> "$P/last"
  done
  # Step 4 (tagged check) + Step 6 (new tags)
  while read -r v sha; do
    if grep -qxE "v?${v}" "$P/remote_tags" "$P/local_tags"; then
      continue
    fi
    echo "${v} ${sha}" >> "$P/new"
  done < "$P/last"
  # Step 6 (release only)
  while read -r line; do
    is_semver "${line}" || continue
    gh release view "${line}" >/dev/null 2>&1 || echo "${line}" >> "$P/release_only"
  done < "$P/remote_tags"
  # Step 6 (latest): all plain X.Y.Z tags after the run; v tags excluded
  { grep -hE '^[0-9]+\.[0-9]+\.[0-9]+$' "$P/remote_tags" "$P/local_tags"; cut -d' ' -f1 "$P/new"; } \
    | semver_sort | tail -n 1 > "$P/latest"
  while read -r tag; do
    if [ "$(printf '%s\n%s\n' "$(cat "$P/latest")" "${tag#v}" | semver_sort | tail -n 1)" = "${tag#v}" ] \
       && [ "${tag#v}" != "$(cat "$P/latest")" ]; then
      echo "\`${tag}\` is higher than the computed Latest \`$(cat "$P/latest")\` — Latest may be wrong, check manually" >> "$P/warnings"
    fi
  done < "$P/v_tags"
  if [ ! -s "$P/new" ] && [ ! -s "$P/release_only" ]; then
    echo "All versions are tagged and released."
  fi
}

plan_row() { # version → "sha7 date title" for a new tag
  local sha title
  sha="$(awk -v v="$1" '$1==v{print $2}' "$P/new")"
  title="$(git log -1 --format=%b "${sha}" | sed -n '/./{p;q;}')"
  [ -n "${title}" ] || title="$(git log -1 --format=%s "${sha}")"
  echo "${sha:0:7} $(git log -1 --format=%cs "${sha}") ${title}"
}

skill_execute() {
  local latest v sha flag
  latest="$(cat "$P/latest")"
  { sed 's/$/ new/' "$P/new" | cut -d' ' -f1,3; sed 's/$/ release/' "$P/release_only"; } \
    | semver_sort > "$P/order"
  while read -r v kind; do
    if [ "${kind}" = "new" ]; then
      sha="$(awk -v v="$v" '$1==v{print $2}' "$P/new")"
      git tag "${v}" "${sha}"
      if ! git push -q origin "refs/tags/${v}" 2>/dev/null; then
        git tag -d "${v}" >/dev/null
        echo "push failed: ${v}" >> "$P/failures"
        continue
      fi
    fi
    flag="--latest=false"
    [ "${v}" = "${latest}" ] && flag="--latest"
    if gh release create "${v}" --verify-tag --title "${v}" --generate-notes "${flag}" >/dev/null; then
      # Step 9: URL per release
      echo "${v} $(gh release view "${v}" --json url --jq .url)" >> "$P/report"
    else
      echo "release failed: ${v}" >> "$P/failures"
    fi
  done < "$P/order"
}

remote_tag_commit() { # tag → commit sha on origin
  git -C "$BASE/origin.git" rev-parse -q --verify "refs/tags/$1^{commit}"
}

# ---------------------------------------------------------------------------
# Runner helpers
# ---------------------------------------------------------------------------

run_test() {
  test_failed=0
  echo "  $1"
  ( "$1" )
  if [ $? -eq 0 ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failures="$failures\n  - $1"
  fi
}

done_test() {
  cd / || exit 1
  [ -n "${BASE:-}" ] && rm -rf "$BASE"
  exit "$test_failed"
}

# ---------------------------------------------------------------------------
# Drift: the mirrored commands are still the documented ones
# ---------------------------------------------------------------------------

test_skill_documents_the_mirrored_git_commands() {
  BASE=""
  assert_skill_has 'gh repo view --json defaultBranchRef --jq .defaultBranchRef.name'
  assert_skill_has 'git fetch origin "<default>" --tags'
  assert_skill_has "git ls-remote --tags --refs origin | sed 's#.*refs/tags/##'"
  assert_skill_has 'git tag --list'
  assert_skill_has 'git rev-list --first-parent --merges --reverse "origin/<default>"'
  assert_skill_has 'version=$(git show "${sha}:${file}" 2>/dev/null | <Read command>)'
  assert_skill_has '^[0-9]+\.[0-9]+\.[0-9]+$'
  assert_skill_has 'git log -1 --format=%cs "${sha}"'
  assert_skill_has 'the path between the backticks on the line starting with `File:`'
  assert_skill_has 'the content of the only fenced `sh` code block in that subsection,'
  assert_skill_has 'used verbatim. Do not add, remove or unescape any character.'
  assert_skill_has 'git show "HEAD:${file}" | <Read command>'
  assert_skill_has "${MSG_NO_SOURCE}\""
  assert_skill_has "${MSG_SELF_CHECK}"
  assert_skill_has 'LC_ALL=C git fetch origin "<default>" --tags'
  assert_skill_has 'decide only by the exit code'
  assert_skill_has '`<oid>\trefs/tags/<tag>` of `git ls-remote --tags --refs origin`'
  assert_skill_has 'local = `git rev-parse -q --verify "refs/tags/<tag>"`'
  assert_skill_has 'local `git rev-parse --short "refs/tags/<tag>^{}"` and the remote `<oid>` (short)'
  assert_skill_has "${MSG_CONFLICT}"
  assert_skill_has "${MSG_FETCH_FAILED}"
  assert_skill_has 'gh release view "<version>" --json url --jq .url'
  assert_skill_has 'Never retry with `--force`, and never delete or move a tag.'
  assert_skill_has "${MSG_V_FORMAT}"
  assert_skill_has "${MSG_LOCAL_ONLY}"
  assert_skill_has 'is higher than the computed Latest `<version>` — Latest may be wrong, check manually'
  assert_skill_has 'all plain `X.Y.Z` tags after the run'
  assert_skill_has "git log -1 --format=%b \"\${sha}\" | sed -n '/./{p;q;}'"
  done_test
}

test_skill_documents_the_mirrored_tag_and_release_commands() {
  BASE=""
  assert_skill_has 'gh release view "<tag>" >/dev/null 2>&1'
  assert_skill_has 'git tag "<version>" "<sha>"'
  assert_skill_has 'git push origin "refs/tags/<version>"'
  assert_skill_has 'git tag -d "<version>"'
  assert_skill_has 'gh release create "<version>" --verify-tag --title "<version>"'
  assert_skill_has '--generate-notes` plus `--latest` for the Latest version and `--latest=false`'
  done_test
}

# ---------------------------------------------------------------------------
# Plan (steps 3-6)
# ---------------------------------------------------------------------------

test_plan_tags_last_merge_of_a_shared_version() {
  make_fixture
  skill_plan
  assert_eq "1.0.0 $(sha_of_merge 4)" "$(grep '^1.0.0 ' "$P/new")" "1.0.0 goes to merge #4, not #3"
  done_test
}

test_plan_contains_exactly_the_untagged_versions() {
  make_fixture
  skill_plan
  assert_eq "1.0.0 2.0.0" "$(cut -d' ' -f1 "$P/new" | tr '\n' ' ' | sed 's/ $//')" "new versions"
  done_test
}

test_plan_skips_version_tagged_on_an_earlier_merge() {
  make_fixture
  skill_plan
  assert_not_contains "$(cat "$P/new")" "1.2.0" "1.2.0 is already tagged"
  done_test
}

test_plan_reports_missing_version_file_as_warning() {
  make_fixture
  skill_plan
  assert_contains "$(cat "$P/warnings")" "$(sha_of_merge 1 | cut -c1-7): no readable version" "warning for #1"
  done_test
}

test_plan_reports_unparsable_version_as_warning_and_continues() {
  make_fixture
  skill_plan
  assert_contains "$(cat "$P/warnings")" "$(sha_of_merge 8 | cut -c1-7): no readable version" "warning for #8"
  assert_contains "$(cat "$P/new")" "2.0.0" "later merges are still scanned"
  done_test
}

test_plan_skips_placeholder_0_0_0_with_note() {
  make_fixture
  skill_plan
  assert_eq "$(sha_of_merge 2 | cut -c1-7): placeholder 0.0.0 skipped" "$(cat "$P/notes")" "notes"
  done_test
}

test_plan_treats_local_v_prefixed_tag_as_tagged_with_warning() {
  make_fixture
  skill_plan
  assert_not_contains "$(cat "$P/new")" "1.3.0" "1.3.0 not planned"
  assert_contains "$(cat "$P/warnings")" "\`v1.3.0\`: ${MSG_LOCAL_ONLY}" "local-only warning"
  done_test
}

test_fixture_has_a_second_parent_merge_with_9_9_9() {
  make_fixture
  side="$(git log --merges --format='%H %s' main | awk '$4=="feature/helper"{print $1}')"
  assert_eq "9.9.9" "$(git show "${side}:${FIXTURE_FILE}" | bash -c "${FIXTURE_READ_CMD}")" "fixture sanity"
  done_test
}

test_plan_ignores_merges_reached_only_via_second_parent() {
  make_fixture
  skill_plan
  assert_not_contains "$(cat "$P/new") $(cat "$P/warnings")" "9.9.9" "9.9.9 never planned"
  done_test
}

test_plan_lists_existing_tag_without_release_as_release_only() {
  make_fixture
  skill_plan
  assert_eq "1.1.0" "$(cat "$P/release_only")" "release-only list"
  done_test
}

test_plan_latest_is_highest_semver_after_the_run() {
  make_fixture
  skill_plan
  assert_eq "2.0.0" "$(cat "$P/latest")" "latest"
  done_test
}

test_plan_row_has_merge_date_and_pr_title_from_body() {
  make_fixture
  skill_plan
  assert_eq "$(sha_of_merge 4 | cut -c1-7) 2026-02-03 PR 4 last 1.0.0" "$(plan_row 1.0.0)" "row for 1.0.0"
  done_test
}

test_plan_row_falls_back_to_subject_without_body() {
  make_fixture
  git checkout -q -b feature/11
  commit_version 3.0.0 "v3"
  git checkout -q main
  git merge -q --no-ff feature/11 -m "Merge pull request #11 from me/feature/11"
  git push -q origin main
  skill_plan
  assert_contains "$(plan_row 3.0.0)" "Merge pull request #11 from me/feature/11" "subject fallback"
  done_test
}

test_plan_changes_nothing_on_origin() {
  make_fixture
  before="$(git ls-remote --tags origin)"
  skill_plan
  assert_eq "$before" "$(git ls-remote --tags origin)" "remote tags after a dry run"
  done_test
}

# ---------------------------------------------------------------------------
# Execute (step 8) and re-run
# ---------------------------------------------------------------------------

test_execute_pushes_new_tags_to_the_planned_commits() {
  make_fixture
  skill_plan
  skill_execute
  assert_eq "$(sha_of_merge 4)" "$(remote_tag_commit 1.0.0)" "1.0.0 on origin"
  assert_eq "$(sha_of_merge 10)" "$(remote_tag_commit 2.0.0)" "2.0.0 on origin"
  done_test
}

test_execute_never_moves_an_existing_tag() {
  make_fixture
  skill_plan
  skill_execute
  assert_eq "$(sha_of_merge 6)" "$(remote_tag_commit 1.2.0)" "1.2.0 stays on merge #6, not the last merge #7"
  done_test
}

test_execute_does_not_push_local_only_tags() {
  make_fixture
  skill_plan
  skill_execute
  assert_eq "" "$(remote_tag_commit v1.3.0)" "v1.3.0 not on origin"
  done_test
}

test_execute_creates_releases_in_semver_order_with_one_latest() {
  make_fixture
  skill_plan
  skill_execute
  assert_eq "1.0.0 --verify-tag --title 1.0.0 --generate-notes --latest=false
1.1.0 --verify-tag --title 1.1.0 --generate-notes --latest=false
2.0.0 --verify-tag --title 2.0.0 --generate-notes --latest" "$(cat "$GH_CREATE_LOG")" "gh release create calls"
  done_test
}

test_backfill_of_older_versions_does_not_take_latest() {
  make_fixture
  git tag 5.0.0 "$(sha_of_merge 9)"
  git push -q origin refs/tags/5.0.0
  echo 5.0.0 >> "$GH_RELEASES"
  skill_plan
  skill_execute
  assert_eq 0 "$(grep -c -- '--latest$' "$GH_CREATE_LOG")" "no release gets --latest"
  assert_contains "$(cat "$GH_CREATE_LOG")" "2.0.0 --verify-tag --title 2.0.0 --generate-notes --latest=false" "2.0.0 not latest"
  done_test
}

test_report_has_release_url_per_created_release() {
  make_fixture
  skill_plan
  skill_execute
  assert_eq "1.0.0 https://github.invalid/releases/tag/1.0.0
1.1.0 https://github.invalid/releases/tag/1.1.0
2.0.0 https://github.invalid/releases/tag/2.0.0" "$(cat "$P/report")" "report URLs"
  done_test
}

test_rerun_after_execute_has_nothing_to_do() {
  make_fixture
  skill_plan
  skill_execute
  out="$(skill_plan)"
  assert_eq "All versions are tagged and released." "$out" "second run"
  done_test
}

test_failed_push_deletes_local_tag_and_skips_release() {
  make_fixture
  cat > "$BASE/origin.git/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
while read -r old new ref; do
  [ "$ref" = "refs/tags/2.0.0" ] && { echo "rejected" >&2; exit 1; }
done
exit 0
HOOK
  chmod +x "$BASE/origin.git/hooks/pre-receive"
  skill_plan
  skill_execute
  assert_eq "" "$(git tag --list 2.0.0)" "local 2.0.0 deleted"
  assert_not_contains "$(cat "$GH_CREATE_LOG")" "2.0.0" "no release for 2.0.0"
  assert_eq "$(sha_of_merge 4)" "$(remote_tag_commit 1.0.0)" "1.0.0 still pushed"
  done_test
}

test_rerun_after_failed_push_retries_only_the_failed_version() {
  make_fixture
  printf '#!/bin/sh\nwhile read o n r; do [ "$r" = refs/tags/2.0.0 ] && exit 1; done; exit 0\n' > "$BASE/origin.git/hooks/pre-receive"
  chmod +x "$BASE/origin.git/hooks/pre-receive"
  skill_plan
  skill_execute
  rm "$BASE/origin.git/hooks/pre-receive"
  skill_plan
  assert_eq "2.0.0 $(sha_of_merge 10)" "$(cat "$P/new")" "only 2.0.0 is left"
  assert_eq "" "$(cat "$P/release_only")" "no release-only work left"
  done_test
}

# ---------------------------------------------------------------------------
# Step 1: version source from the profile
# ---------------------------------------------------------------------------

test_source_file_is_read_from_the_file_line() {
  make_fixture
  skill_load_source
  assert_eq "${FIXTURE_FILE}" "${FILE}" "file"
  done_test
}

test_source_read_command_is_the_sh_block_verbatim() {
  make_fixture
  skill_load_source
  assert_eq "${FIXTURE_READ_CMD}" "${READ_CMD}" "read command"
  done_test
}

test_source_self_check_passes_on_head() {
  make_fixture
  out="$(skill_load_source)"
  assert_eq 0 "$?" "exit code"
  assert_eq "" "${out}" "no stop message"
  done_test
}

test_source_ignores_file_lines_and_blocks_of_other_sections() {
  make_fixture
  skill_plan >/dev/null
  assert_not_contains "$(cat "$P/new")" "6.6.6" "block of another section not used"
  done_test
}

test_missing_version_source_subsection_stops() {
  make_fixture
  write_profile "File: \`${FIXTURE_FILE}\`" "${FIXTURE_READ_CMD}" "### Something else"
  assert_eq "STOP: ${MSG_NO_SOURCE}" "$(skill_plan)" "stop message"
  done_test
}

test_missing_file_line_stops() {
  make_fixture
  write_profile "" "${FIXTURE_READ_CMD}"
  assert_eq "STOP: ${MSG_NO_SOURCE}" "$(skill_plan)" "stop message"
  done_test
}

test_missing_sh_block_stops() {
  make_fixture
  write_profile "File: \`${FIXTURE_FILE}\`" ""
  assert_eq "STOP: ${MSG_NO_SOURCE}" "$(skill_plan)" "stop message"
  done_test
}

test_self_check_stops_when_read_command_prints_nothing() {
  make_fixture
  write_profile "File: \`${FIXTURE_FILE}\`" "awk '/no-such-line/'"
  assert_contains "$(skill_plan)" "STOP: ${MSG_SELF_CHECK}" "stop message"
  done_test
}

test_self_check_stops_for_a_markdown_escaped_pipe() {
  # The revision 5 bug: a table-cell escape `\|` taken verbatim breaks sed.
  make_fixture
  write_profile "File: \`${FIXTURE_FILE}\`" "sed -nE 's/^  \"version\": \"([^\"]+)\".*/\\1/p' \\| head -n 1"
  assert_contains "$(skill_plan)" "STOP: ${MSG_SELF_CHECK}" "stop message"
  done_test
}

test_self_check_stops_when_file_is_wrong() {
  make_fixture
  write_profile "File: \`app/missing.json\`" "${FIXTURE_READ_CMD}"
  assert_contains "$(skill_plan)" "STOP: ${MSG_SELF_CHECK}" "stop message"
  done_test
}

test_self_check_stop_creates_no_tags() {
  make_fixture
  before="$(git ls-remote --tags origin)"
  write_profile "File: \`app/missing.json\`" "${FIXTURE_READ_CMD}"
  skill_plan >/dev/null
  assert_eq "${before}" "$(git ls-remote --tags origin)" "remote tags"
  done_test
}

# ---------------------------------------------------------------------------
# Step 3: fetch tag conflict
# ---------------------------------------------------------------------------

make_conflict() { # local 1.1.0 on merge #4, origin's 1.1.0 is on merge #5
  git tag -f 1.1.0 "$(sha_of_merge 4)" >/dev/null
}

test_fetch_conflict_stops_with_conflict_message() {
  make_fixture
  make_conflict
  out="$(skill_plan)"
  assert_eq 1 "$?" "skill_plan returns 1"
  assert_contains "${out}" "STOP: ${MSG_CONFLICT}" "stop message"
  done_test
}

test_fetch_conflict_lists_tag_with_local_and_remote_oid() {
  make_fixture
  make_conflict
  out="$(skill_plan)"
  assert_contains "${out}" "conflict: 1.1.0 local $(git rev-parse --short "$(sha_of_merge 4)") remote $(sha_of_merge 5 | cut -c1-7)" "conflict line"
  done_test
}

test_fetch_conflict_lists_only_the_conflicting_tag() {
  make_fixture
  make_conflict
  out="$(skill_plan)"
  assert_not_contains "${out}" "conflict: 1.2.0" "1.2.0 is identical on both sides"
  done_test
}

test_fetch_conflict_is_listed_under_a_german_locale() {
  make_fixture
  make_conflict
  out="$(LC_ALL=de_DE.UTF-8 LANG=de_DE.UTF-8 skill_plan)"
  assert_contains "${out}" "conflict: 1.1.0 local $(git rev-parse --short "$(sha_of_merge 4)") remote $(sha_of_merge 5 | cut -c1-7)" "conflict line"
  assert_contains "${out}" "STOP: ${MSG_CONFLICT}" "stop message"
  done_test
}

test_fetch_conflict_is_listed_under_c_locale() {
  make_fixture
  make_conflict
  out="$(LC_ALL=C LANG=C skill_plan)"
  assert_contains "${out}" "conflict: 1.1.0 local $(git rev-parse --short "$(sha_of_merge 4)") remote $(sha_of_merge 5 | cut -c1-7)" "conflict line"
  done_test
}

test_fetch_conflict_changes_no_tag() {
  make_fixture
  make_conflict
  skill_plan >/dev/null
  assert_eq "$(sha_of_merge 4)" "$(git rev-parse 1.1.0)" "local 1.1.0 unchanged"
  assert_eq "$(sha_of_merge 5)" "$(remote_tag_commit 1.1.0)" "remote 1.1.0 unchanged"
  assert_eq "" "$(cat "$GH_CREATE_LOG")" "no release"
  done_test
}

test_fetch_failure_without_conflict_stops_with_fetch_failed() {
  make_fixture
  git remote set-url origin "$BASE/no-such-origin.git"
  out="$(skill_plan)"
  assert_eq 1 "$?" "skill_plan returns 1"
  assert_contains "${out}" "STOP: ${MSG_FETCH_FAILED}" "stop message"
  assert_not_contains "${out}" "${MSG_CONFLICT}" "no conflict message"
  done_test
}

test_fetch_failure_shows_the_git_error() {
  make_fixture
  git remote set-url origin "$BASE/no-such-origin.git"
  out="$(skill_plan)"
  assert_contains "${out}" "no-such-origin.git" "git error output shown"
  done_test
}

# ---------------------------------------------------------------------------
# v-prefixed tags (non-standard format)
# ---------------------------------------------------------------------------

push_remote_v_tag() { # tag  merge-number
  git tag "$1" "$(sha_of_merge "$2")"
  git push -q origin "refs/tags/$1"
}

test_v_tag_is_warned_as_non_standard_format() {
  make_fixture
  skill_plan
  assert_contains "$(cat "$P/warnings")" "\`v1.3.0\`: ${MSG_V_FORMAT}" "format warning"
  done_test
}

test_remote_v_tag_blocks_a_duplicate_plain_tag() {
  make_fixture
  push_remote_v_tag v2.0.0 10
  skill_plan
  assert_eq "1.0.0" "$(cut -d' ' -f1 "$P/new")" "2.0.0 not planned"
  done_test
}

test_remote_v_tag_gets_no_release() {
  make_fixture
  push_remote_v_tag v2.0.0 10
  skill_plan
  assert_eq "1.1.0" "$(cat "$P/release_only")" "release-only list"
  done_test
}

test_v_tag_is_excluded_from_latest() {
  make_fixture
  push_remote_v_tag v2.0.0 10
  skill_plan
  assert_eq "1.2.0" "$(cat "$P/latest")" "latest from plain tags"
  done_test
}

test_higher_v_tag_than_latest_is_warned() {
  make_fixture
  push_remote_v_tag v2.0.0 10
  skill_plan
  assert_contains "$(cat "$P/warnings")" "\`v2.0.0\` is higher than the computed Latest \`1.2.0\` — Latest may be wrong, check manually" "higher-v warning"
  done_test
}

test_lower_v_tag_gives_no_higher_warning() {
  make_fixture
  skill_plan
  assert_not_contains "$(cat "$P/warnings")" "is higher than the computed Latest" "no higher-v warning"
  done_test
}

test_execute_with_higher_v_tag_sets_no_latest() {
  make_fixture
  push_remote_v_tag v2.0.0 10
  skill_plan
  skill_execute
  assert_eq "1.0.0 --verify-tag --title 1.0.0 --generate-notes --latest=false
1.1.0 --verify-tag --title 1.1.0 --generate-notes --latest=false" "$(cat "$GH_CREATE_LOG")" "gh release create calls"
  done_test
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

echo "tag-releases tests ($SKILL_MD, $(git --version))"
build_template
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  run_test "$t"
done
rm -rf "$TEMPLATE"

echo
echo "$passed passed, $failed failed"
if [ "$failed" -ne 0 ]; then
  printf "Failed tests:%b\n" "$failures"
  exit 1
fi
