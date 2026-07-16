#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
## Author: Tito Valentin
## Name of Program: dirPathPerms test suite
## Date Created: 2026-07-16
## Description: Black-box tests for dirPathPerms.sh. Drives the real CLI against
##              generated fixtures and asserts the reported result for each of
##              the path spellings a user can realistically put in an input file.

set -uo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$SCRIPT_DIR/dirPathPerms.sh"

pass=0
fail=0

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Colors only when a terminal is attached, matching the script's own behavior.
if [[ -t 1 ]]; then
  T_RED=$'\e[1;31m' T_GREEN=$'\e[1;32m' T_BOLD=$'\e[1m' T_RESET=$'\e[0m'
else
  T_RED="" T_GREEN="" T_BOLD="" T_RESET=""
fi

# run_case <name> <paths-file-content> <expected-substring>
#
# Writes the content verbatim to a paths file, runs an owner/read check over it,
# and asserts the expected substring shows up in the result output.
run_case() {
  local name="$1" content="$2" expect="$3"
  local paths="$WORK/paths.txt" out

  printf '%b' "$content" > "$paths"
  out=$("$SCRIPT" --file "$paths" --who owner --perm read --no-color 2>/dev/null)

  if [[ "$out" == *"$expect"* ]]; then
    printf '  %sPASS%s  %s\n' "$T_GREEN" "$T_RESET" "$name"
    pass=$((pass + 1))
  else
    printf '  %sFAIL%s  %s\n' "$T_RED" "$T_RESET" "$name"
    printf '        expected to find: %s\n' "$expect"
    printf '        actual output:\n'
    printf '%s\n' "$out" | sed 's/^/          /'
    fail=$((fail + 1))
  fi
}

# run_summary_case <name> <paths-file-content> <expected-substring>
#
# Same, but asserts against the summary line, which the script writes to stderr
# along with the rest of its chrome so that stdout stays pipe-friendly.
run_summary_case() {
  local name="$1" content="$2" expect="$3"
  local paths="$WORK/paths.txt" out

  printf '%b' "$content" > "$paths"
  out=$("$SCRIPT" --file "$paths" --who owner --perm read --no-color 2>&1 >/dev/null)

  if [[ "$out" == *"$expect"* ]]; then
    printf '  %sPASS%s  %s\n' "$T_GREEN" "$T_RESET" "$name"
    pass=$((pass + 1))
  else
    printf '  %sFAIL%s  %s\n' "$T_RED" "$T_RESET" "$name"
    printf '        expected to find: %s\n' "$expect"
    printf '        actual stderr:\n'
    printf '%s\n' "$out" | sed 's/^/          /'
    fail=$((fail + 1))
  fi
}

# run_argv_case <name> <expected-substring> <args...>
#
# Runs the CLI with arbitrary arguments, asserting against stdout and stderr
# together so that both results and error messages can be checked.
run_argv_case() {
  local name="$1" expect="$2"
  shift 2
  local out
  out=$("$SCRIPT" --no-color "$@" 2>&1)

  if [[ "$out" == *"$expect"* ]]; then
    printf '  %sPASS%s  %s\n' "$T_GREEN" "$T_RESET" "$name"
    pass=$((pass + 1))
  else
    printf '  %sFAIL%s  %s\n' "$T_RED" "$T_RESET" "$name"
    printf '        expected to find: %s\n' "$expect"
    printf '        actual output:\n'
    printf '%s\n' "$out" | sed 's/^/          /'
    fail=$((fail + 1))
  fi
}

# refute_case <name> <paths-file-content> <forbidden-substring>
refute_case() {
  local name="$1" content="$2" forbidden="$3"
  local paths="$WORK/paths.txt" out

  printf '%b' "$content" > "$paths"
  out=$("$SCRIPT" --file "$paths" --who owner --perm read --no-color 2>/dev/null)

  if [[ "$out" != *"$forbidden"* ]]; then
    printf '  %sPASS%s  %s\n' "$T_GREEN" "$T_RESET" "$name"
    pass=$((pass + 1))
  else
    printf '  %sFAIL%s  %s\n' "$T_RED" "$T_RESET" "$name"
    printf '        expected NOT to find: %s\n' "$forbidden"
    printf '        actual output:\n'
    printf '%s\n' "$out" | sed 's/^/          /'
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------------------
# Fixtures.
# ---------------------------------------------------------------------------
FIX="$WORK/fixtures"
mkdir -p "$FIX"
printf 'x\n' > "$FIX/plain.txt"
printf 'x\n' > "$FIX/my file.txt"        # a space, as macOS filenames often have
chmod 644 "$FIX/plain.txt" "$FIX/my file.txt"

# A file whose name genuinely contains characters the normalizer expands. It
# must still be checked literally rather than mangled into something else.
printf 'x\n' > "$FIX/lit_\$HOME.txt"
chmod 644 "$FIX/lit_\$HOME.txt"

# A real list-of-paths file, for the cases that assert list mode still applies.
printf '%s\n' "$FIX/plain.txt" > "$WORK/list_of_paths.txt"

# A file under the real home directory, for the tilde and $HOME cases.
HOME_FIX=$(mktemp "$HOME/.dirpathperms_test_XXXXXX")
chmod 644 "$HOME_FIX"
HOME_REL="${HOME_FIX#"$HOME"/}"
trap 'rm -rf "$WORK"; rm -f "$HOME_FIX"' EXIT

ME=$(id -un)

printf '\n%sdirPathPerms test suite%s\n\n' "$T_BOLD" "$T_RESET"

# ---------------------------------------------------------------------------
# Baseline: the spelling that already worked must keep working.
# ---------------------------------------------------------------------------
run_case "plain absolute path" \
  "$FIX/plain.txt\n" "YES"

run_case "absolute path containing a literal space" \
  "$FIX/my file.txt\n" "YES"

run_case "missing path is still reported as skipped" \
  "/no/such/path/anywhere\n" "SKIP (path does not exist)"

# ---------------------------------------------------------------------------
# DIR-2: the spellings that used to be reported as nonexistent.
# ---------------------------------------------------------------------------
# The tildes in these fixtures are literal text written into the input file for
# the script to parse, not paths for this shell to expand (SC2088).
# shellcheck disable=SC2088
run_case "tilde: ~/path" \
  "~/$HOME_REL\n" "YES"

run_case "tilde: bare ~ (the home directory itself)" \
  "~\n" "YES"

run_case "tilde: ~user" \
  "~$ME\n" "YES"

run_case "env var: \$HOME/path" \
  "\$HOME/$HOME_REL\n" "YES"

run_case "env var: \${HOME}/path" \
  "\${HOME}/$HOME_REL\n" "YES"

run_case "backslash-escaped space (Finder drag-and-drop)" \
  "$FIX/my\\\\ file.txt\n" "YES"

run_case "double-quoted path" \
  "\"$FIX/my file.txt\"\n" "YES"

run_case "single-quoted path" \
  "'$FIX/my file.txt'\n" "YES"

run_case "leading whitespace" \
  "    $FIX/plain.txt\n" "YES"

run_case "trailing whitespace" \
  "$FIX/plain.txt   \n" "YES"

run_case "CRLF line ending" \
  "$FIX/plain.txt\r\n" "YES"

refute_case "CRLF blank line is not treated as a path" \
  "\r\n$FIX/plain.txt\r\n" "SKIP"

run_summary_case "CRLF file counts only the real path" \
  "\r\n$FIX/plain.txt\r\n" "1 granted"

refute_case "indented comment is still a comment" \
  "   # a comment\n$FIX/plain.txt\n" "SKIP"

run_summary_case "indented comment is not counted as a path" \
  "   # a comment\n$FIX/plain.txt\n" "1 granted"

# ---------------------------------------------------------------------------
# The literal fallback: expansion must never make a real file unreachable.
# ---------------------------------------------------------------------------
run_case "file whose name literally contains \$HOME" \
  "$FIX/lit_\$HOME.txt\n" "YES"

# ---------------------------------------------------------------------------
# Safety: an input file names files, it does not run commands.
# ---------------------------------------------------------------------------
refute_case "command substitution is not executed" \
  "/tmp/\$(id -un)\n" "$(id -un)/"

run_case "command substitution is left literal" \
  "/tmp/\$(id -un)\n" 'SKIP (path does not exist)'

refute_case "backticks are not executed" \
  "/tmp/\`id -un\`\n" "$(id -un)"

# ---------------------------------------------------------------------------
# DIR-2: checking a path directly, without authoring a list file first.
# ---------------------------------------------------------------------------
run_argv_case "--path checks a directory directly" \
  "YES" --path "$FIX" --who owner --perm read

run_argv_case "--path expands a tilde" \
  "$HOME" --path "~" --who owner --perm read

run_argv_case "--path is repeatable" \
  "2 paths given" --path "$FIX" --path "$FIX/plain.txt" --who owner --perm read

run_argv_case "a bare directory argument is checked directly" \
  "YES" --who owner --perm read "$FIX"

run_argv_case "a bare regular-file argument is still read as a list" \
  "YES" --who owner --perm read "$WORK/list_of_paths.txt"

run_argv_case "a bare missing argument says so" \
  "No such path" --who owner --perm read "/no/such/path/anywhere"

# The screenshot bug: a directory given where a list was expected used to be
# reported as "file not found", which is not true — it exists.
run_argv_case "--file on a directory names the real problem" \
  "is a directory, not a list of paths" --file "$FIX" --who owner --perm read

refute_case_argv_not_found() {
  local out
  out=$("$SCRIPT" --no-color --file "$FIX" --who owner --perm read 2>&1)
  if [[ "$out" != *"file not found"* ]]; then
    printf '  %sPASS%s  %s\n' "$T_GREEN" "$T_RESET" "--file on a directory no longer claims 'file not found'"
    pass=$((pass + 1))
  else
    printf '  %sFAIL%s  %s\n' "$T_RED" "$T_RESET" "--file on a directory no longer claims 'file not found'"
    fail=$((fail + 1))
  fi
}
refute_case_argv_not_found

run_argv_case "--file and --path together is refused" \
  "cannot be combined" --file "$WORK/list_of_paths.txt" --path /etc --who owner --perm read

run_argv_case "--path with no value is refused" \
  "requires a value" --path

# ---------------------------------------------------------------------------
# The interactive surface needs a real terminal, so it lives in a pty harness.
# ---------------------------------------------------------------------------
if command -v python3 >/dev/null 2>&1; then
  if python3 "$SCRIPT_DIR/tests/interactive_test.py"; then
    pass=$((pass + 1))
  else
    printf '  %sFAIL%s  interactive (pty) tests\n' "$T_RED" "$T_RESET"
    fail=$((fail + 1))
  fi
else
  printf '  %sSKIP%s  interactive (pty) tests — python3 not available\n' \
    "$T_BOLD" "$T_RESET"
fi

# ---------------------------------------------------------------------------
printf '\n%sSummary:%s %s passed, %s failed\n\n' \
  "$T_BOLD" "$T_RESET" "$pass" "$fail"

[[ "$fail" -eq 0 ]]
