#!/usr/bin/env bash
# Tests for scripts/link.sh (link mode and --check).
#
# Usage: tests/link.test.sh            (from the ai-base root or anywhere else)
#
# Testing concept:
# - Level: black-box tests of the script as a user runs it. Every test builds a
#   throwaway project in a temp directory with a fake `.ai-base/` (handbook, two
#   agents, one skill, SPEC.md and a copy of the real scripts/link.sh), runs
#   `.ai-base/scripts/link.sh [--check]` from the project root and asserts on
#   exit code, output and the resulting file system (link text, regular files).
# - Covered: help and unknown arguments, uninitialized .ai-base (exit 2),
#   creating links with the exact link text, idempotency, overrides (regular
#   files are never touched and are reported), MISSING/WRONG/BROKEN/STALE in
#   --check with exit codes, re-pointing wrong links, stale link cleanup
#   (including empty skill directories), and links that do not point into
#   .ai-base/ being ignored.
# - Not covered: Windows without core.symlinks, git index modes (verified per
#   project with `git ls-files -s`, see README "Update a project").
# - Needs only bash (3.2+), coreutils and a writable temp directory. No network.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINK_SH="$ROOT/scripts/link.sh"

passed=0
failed=0
failures=""
current=""
test_failed=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Creates a project with a fake, initialized .ai-base in a new temp dir and
# changes into it.
make_project() {
  PROJECT="$(mktemp -d "${TMPDIR:-/tmp}/ai-base link test.XXXXXX")"
  mkdir -p "$PROJECT/.ai-base/agents" "$PROJECT/.ai-base/skills/one" "$PROJECT/.ai-base/scripts"
  echo "handbook" > "$PROJECT/.ai-base/handbook.md"
  echo "alpha agent" > "$PROJECT/.ai-base/agents/alpha.md"
  echo "beta agent" > "$PROJECT/.ai-base/agents/beta.md"
  echo "skill one" > "$PROJECT/.ai-base/skills/one/SKILL.md"
  echo "spec" > "$PROJECT/.ai-base/SPEC.md"
  cp "$LINK_SH" "$PROJECT/.ai-base/scripts/link.sh"
  chmod +x "$PROJECT/.ai-base/scripts/link.sh"
  cd "$PROJECT" || exit 1
}

# Runs link.sh with the given arguments; stores stdout+stderr in OUT and the
# exit code in CODE.
run_link() {
  OUT="$(.ai-base/scripts/link.sh "$@" 2>&1)"
  CODE=$?
}

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
    *) fail "$3: [$2] not in output: [$1]" ;;
  esac
}

assert_not_contains() { # haystack needle message
  case "$1" in
    *"$2"*) fail "$3: unexpected [$2] in output: [$1]" ;;
    *) ;;
  esac
}

assert_link() { # path expected-link-text
  if [ ! -L "$1" ]; then
    fail "$1 is not a symlink"
  else
    assert_eq "$2" "$(readlink "$1")" "link text of $1"
  fi
}

assert_regular_file() { # path expected-content
  if [ -L "$1" ] || [ ! -f "$1" ]; then
    fail "$1 is not a regular file"
  else
    assert_eq "$2" "$(cat "$1")" "content of $1"
  fi
}

assert_absent() { # path
  if [ -e "$1" ] || [ -L "$1" ]; then
    fail "$1 should not exist"
  fi
}

count_lines() { # text prefix
  printf '%s\n' "$1" | grep -c "^$2" || true
}

run_test() {
  current="$1"
  test_failed=0
  echo "  $current"
  ( "$current" )
  # The subshell exits non-zero if any assertion failed (see end of each test).
  if [ $? -eq 0 ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failures="$failures\n  - $current"
  fi
}

# Every test ends with `done_test`, which cleans up and reports the result.
done_test() {
  cd / || exit 1
  rm -rf "$PROJECT"
  exit "$test_failed"
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

test_help_prints_usage_and_exits_0() {
  make_project
  run_link --help
  assert_eq 0 "$CODE" "exit code"
  assert_contains "$OUT" "Usage: .ai-base/scripts/link.sh [--check]" "usage line"
  done_test
}

test_short_help_flag_exits_0() {
  make_project
  run_link -h
  assert_eq 0 "$CODE" "exit code"
  assert_contains "$OUT" "Usage:" "usage line"
  done_test
}

test_help_does_not_create_links() {
  make_project
  run_link --help
  assert_absent .claude
  done_test
}

test_unknown_argument_exits_2_with_message() {
  make_project
  run_link --bogus
  assert_eq 2 "$CODE" "exit code"
  assert_contains "$OUT" "Unknown argument: --bogus" "error message"
  done_test
}

test_unknown_argument_does_not_create_links() {
  make_project
  run_link --bogus
  assert_absent SPEC.md
  done_test
}

# ---------------------------------------------------------------------------
# Uninitialized submodule
# ---------------------------------------------------------------------------

test_uninitialized_ai_base_exits_2_in_link_mode() {
  make_project
  rm .ai-base/handbook.md
  run_link
  assert_eq 2 "$CODE" "exit code"
  assert_contains "$OUT" ".ai-base is not initialized — run: git submodule update --init" "message"
  done_test
}

test_uninitialized_ai_base_exits_2_in_check_mode() {
  make_project
  rm .ai-base/handbook.md
  run_link --check
  assert_eq 2 "$CODE" "exit code"
  done_test
}

test_uninitialized_ai_base_creates_nothing() {
  make_project
  rm .ai-base/handbook.md
  run_link
  assert_absent .claude
  done_test
}

# ---------------------------------------------------------------------------
# Link mode: creating links
# ---------------------------------------------------------------------------

test_link_creates_claude_agent_links() {
  make_project
  run_link
  assert_link .claude/agents/alpha.md ../../.ai-base/agents/alpha.md
  assert_link .claude/agents/beta.md ../../.ai-base/agents/beta.md
  done_test
}

test_link_creates_github_agent_links_with_agent_suffix() {
  make_project
  run_link
  assert_link .github/agents/alpha.agent.md ../../.ai-base/agents/alpha.md
  assert_link .github/agents/beta.agent.md ../../.ai-base/agents/beta.md
  done_test
}

test_link_creates_skill_links_for_both_tools() {
  make_project
  run_link
  assert_link .claude/skills/one/SKILL.md ../../../.ai-base/skills/one/SKILL.md
  assert_link .github/skills/one/SKILL.md ../../../.ai-base/skills/one/SKILL.md
  done_test
}

test_link_creates_spec_link() {
  make_project
  run_link
  assert_link SPEC.md .ai-base/SPEC.md
  done_test
}

test_created_links_resolve_to_ai_base_content() {
  make_project
  run_link
  assert_eq "beta agent" "$(cat .github/agents/beta.agent.md)" "resolved agent"
  assert_eq "skill one" "$(cat .claude/skills/one/SKILL.md)" "resolved skill"
  done_test
}

test_link_exits_0_and_reports_every_link() {
  make_project
  run_link
  assert_eq 0 "$CODE" "exit code"
  assert_eq 7 "$(count_lines "$OUT" "linked: ")" "number of linked: lines"
  done_test
}

test_link_works_in_a_path_with_spaces() {
  make_project
  run_link
  assert_contains "$PROJECT" " " "temp path contains a space"
  assert_eq "spec" "$(cat SPEC.md)" "resolved SPEC.md"
  done_test
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

test_second_link_run_keeps_links_unchanged() {
  make_project
  run_link
  run_link
  assert_eq 0 "$CODE" "exit code"
  assert_link .claude/agents/alpha.md ../../.ai-base/agents/alpha.md
  assert_link .github/skills/one/SKILL.md ../../../.ai-base/skills/one/SKILL.md
  done_test
}

test_second_link_run_removes_nothing() {
  make_project
  run_link
  run_link
  assert_not_contains "$OUT" "removed stale" "second run output"
  done_test
}

test_second_link_run_does_not_nest_links_into_directories() {
  make_project
  run_link
  run_link
  assert_absent .ai-base/skills/one/SKILL.md/SKILL.md
  assert_absent .ai-base/agents/alpha.md.md
  done_test
}

# ---------------------------------------------------------------------------
# Check mode: clean state and MISSING
# ---------------------------------------------------------------------------

test_check_after_link_exits_0_silently() {
  make_project
  run_link
  run_link --check
  assert_eq 0 "$CODE" "exit code"
  assert_eq "" "$OUT" "output"
  done_test
}

test_check_on_unlinked_project_reports_missing_and_exits_1() {
  make_project
  run_link --check
  assert_eq 1 "$CODE" "exit code"
  assert_eq 7 "$(count_lines "$OUT" "MISSING: ")" "number of MISSING: lines"
  done_test
}

test_check_reports_missing_spec() {
  make_project
  run_link
  rm SPEC.md
  run_link --check
  assert_eq 1 "$CODE" "exit code"
  assert_eq "MISSING: SPEC.md" "$OUT" "output"
  done_test
}

test_check_does_not_create_links() {
  make_project
  run_link --check
  assert_absent .claude
  assert_absent SPEC.md
  done_test
}

# ---------------------------------------------------------------------------
# Overrides (regular files)
# ---------------------------------------------------------------------------

test_link_leaves_regular_spec_file_untouched() {
  make_project
  echo "project spec" > SPEC.md
  run_link
  assert_regular_file SPEC.md "project spec"
  done_test
}

test_link_reports_regular_spec_file_as_override() {
  make_project
  echo "project spec" > SPEC.md
  run_link
  assert_contains "$OUT" "override: SPEC.md" "override line"
  assert_not_contains "$OUT" "linked: SPEC.md" "no linked line for SPEC.md"
  done_test
}

test_link_leaves_regular_agent_file_untouched() {
  make_project
  mkdir -p .claude/agents
  echo "project alpha" > .claude/agents/alpha.md
  run_link
  assert_regular_file .claude/agents/alpha.md "project alpha"
  assert_contains "$OUT" "override: .claude/agents/alpha.md" "override line"
  done_test
}

test_override_does_not_block_the_other_tool() {
  make_project
  mkdir -p .claude/agents
  echo "project alpha" > .claude/agents/alpha.md
  run_link
  assert_link .github/agents/alpha.agent.md ../../.ai-base/agents/alpha.md
  done_test
}

test_check_accepts_override_and_exits_0() {
  make_project
  run_link
  rm .claude/skills/one/SKILL.md
  echo "project skill" > .claude/skills/one/SKILL.md
  run_link --check
  assert_eq 0 "$CODE" "exit code"
  assert_eq "override: .claude/skills/one/SKILL.md" "$OUT" "output"
  done_test
}

test_project_only_agent_is_ignored() {
  make_project
  mkdir -p .claude/agents
  echo "custom" > .claude/agents/custom.md
  run_link
  run_link --check
  assert_eq 0 "$CODE" "exit code"
  assert_regular_file .claude/agents/custom.md "custom"
  done_test
}

# ---------------------------------------------------------------------------
# WRONG / BROKEN
# ---------------------------------------------------------------------------

test_check_reports_wrong_link_text_and_exits_1() {
  make_project
  run_link
  ln -sfn ../../.ai-base/agents/beta.md .claude/agents/alpha.md
  run_link --check
  assert_eq 1 "$CODE" "exit code"
  assert_eq "WRONG: .claude/agents/alpha.md" "$OUT" "output"
  done_test
}

test_check_reports_legacy_link_as_wrong() {
  make_project
  mkdir -p docs/agents .github/agents
  echo "legacy" > docs/agents/alpha.md
  run_link
  ln -sfn ../../docs/agents/alpha.md .github/agents/alpha.agent.md
  run_link --check
  assert_eq 1 "$CODE" "exit code"
  assert_contains "$OUT" "WRONG: .github/agents/alpha.agent.md" "WRONG line"
  done_test
}

test_link_repoints_wrong_link() {
  make_project
  mkdir -p docs/agents .claude/agents
  echo "legacy" > docs/agents/alpha.md
  ln -s ../../docs/agents/alpha.md .claude/agents/alpha.md
  run_link
  assert_link .claude/agents/alpha.md ../../.ai-base/agents/alpha.md
  done_test
}

test_link_repoints_wrong_link_that_points_to_a_directory() {
  make_project
  mkdir -p docs/agents .claude/agents
  ln -s ../../docs/agents .claude/agents/alpha.md
  run_link
  assert_link .claude/agents/alpha.md ../../.ai-base/agents/alpha.md
  assert_absent docs/agents/agents
  done_test
}

test_link_repoints_wrong_link_that_points_into_ai_base_at_wrong_depth() {
  make_project
  mkdir -p .claude/agents
  ln -s ../.ai-base/agents/alpha.md .claude/agents/alpha.md
  run_link
  assert_link .claude/agents/alpha.md ../../.ai-base/agents/alpha.md
  assert_not_contains "$OUT" "removed stale" "re-pointed link is not removed"
  done_test
}

test_check_reports_broken_spec_link_and_exits_1() {
  make_project
  run_link
  rm .ai-base/SPEC.md
  run_link --check
  assert_eq 1 "$CODE" "exit code"
  assert_eq "BROKEN: SPEC.md" "$OUT" "output"
  done_test
}

test_check_reports_every_problem_not_only_the_first() {
  make_project
  run_link
  rm SPEC.md .github/agents/beta.agent.md
  ln -sfn ../../.ai-base/agents/beta.md .claude/agents/alpha.md
  run_link --check
  assert_eq 1 "$CODE" "exit code"
  assert_contains "$OUT" "WRONG: .claude/agents/alpha.md" "WRONG line"
  assert_contains "$OUT" "MISSING: .github/agents/beta.agent.md" "MISSING agent line"
  assert_contains "$OUT" "MISSING: SPEC.md" "MISSING SPEC line"
  done_test
}

# ---------------------------------------------------------------------------
# STALE links
# ---------------------------------------------------------------------------

test_check_reports_stale_agent_link_and_exits_1() {
  make_project
  run_link
  ln -s ../../.ai-base/agents/old.md .claude/agents/old.md
  run_link --check
  assert_eq 1 "$CODE" "exit code"
  assert_eq "STALE: .claude/agents/old.md" "$OUT" "output"
  done_test
}

test_check_does_not_remove_stale_links() {
  make_project
  run_link
  ln -s ../../.ai-base/agents/old.md .claude/agents/old.md
  run_link --check
  assert_link .claude/agents/old.md ../../.ai-base/agents/old.md
  done_test
}

test_link_removes_stale_agent_link() {
  make_project
  run_link
  ln -s ../../.ai-base/agents/old.md .github/agents/old.agent.md
  run_link
  assert_absent .github/agents/old.agent.md
  assert_contains "$OUT" "removed stale: .github/agents/old.agent.md" "removed line"
  done_test
}

test_link_removes_stale_skill_link_and_its_empty_directory() {
  make_project
  run_link
  mkdir -p .claude/skills/gone
  ln -s ../../../.ai-base/skills/gone/SKILL.md .claude/skills/gone/SKILL.md
  run_link
  assert_absent .claude/skills/gone
  assert_contains "$OUT" "removed stale: .claude/skills/gone/SKILL.md" "removed line"
  done_test
}

test_link_keeps_skill_directory_with_project_files() {
  make_project
  run_link
  mkdir -p .github/skills/gone
  ln -s ../../../.ai-base/skills/gone/SKILL.md .github/skills/gone/SKILL.md
  echo "notes" > .github/skills/gone/notes.md
  run_link
  assert_absent .github/skills/gone/SKILL.md
  assert_regular_file .github/skills/gone/notes.md "notes"
  done_test
}

test_agent_removed_from_ai_base_is_reported_stale_for_both_tools() {
  make_project
  run_link
  rm .ai-base/agents/beta.md
  run_link --check
  assert_eq 1 "$CODE" "exit code"
  assert_contains "$OUT" "STALE: .claude/agents/beta.md" "claude STALE line"
  assert_contains "$OUT" "STALE: .github/agents/beta.agent.md" "github STALE line"
  done_test
}

test_check_is_clean_after_relinking_a_removed_agent() {
  make_project
  run_link
  rm .ai-base/agents/beta.md
  run_link
  run_link --check
  assert_eq 0 "$CODE" "exit code"
  assert_absent .claude/agents/beta.md
  done_test
}

test_broken_link_outside_ai_base_is_ignored() {
  make_project
  run_link
  ln -s ../../somewhere/else.md .claude/agents/foreign.md
  run_link
  run_link --check
  assert_eq 0 "$CODE" "exit code"
  assert_link .claude/agents/foreign.md ../../somewhere/else.md
  done_test
}

# ---------------------------------------------------------------------------
# Repository file properties
# ---------------------------------------------------------------------------

test_link_script_is_executable() {
  make_project
  [ -x "$LINK_SH" ] || fail "$LINK_SH is not executable"
  done_test
}

# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

echo "link.sh tests ($LINK_SH, $(bash --version | head -1))"
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  run_test "$t"
done

echo
echo "$passed passed, $failed failed"
if [ "$failed" -ne 0 ]; then
  printf "Failed tests:%b\n" "$failures"
  exit 1
fi
