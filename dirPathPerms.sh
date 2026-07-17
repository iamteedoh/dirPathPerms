#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
## Author: Tito Valentin
## Name of Program: dirPathPerms.sh
## Date Created: 2026-07-13
## Description: Interactive and non-interactive checker that reports whether a
##              chosen permission (read/write/execute) is set for the owner,
##              group, or other on the paths it is given — either named
##              directly or listed one per line in an input file.

set -uo pipefail

VERSION="0.1.0"

# ---------------------------------------------------------------------------
# Colors. Disabled when --no-color / $NO_COLOR is set, or stdout is not a TTY
# (so redirected/piped output stays clean and free of escape codes).
# ---------------------------------------------------------------------------
USE_COLOR="auto"
setup_colors() {
  if [[ "$USE_COLOR" == "no" || -n "${NO_COLOR:-}" || ! -t 1 ]]; then
    BOLD="" DIM="" RED="" GREEN="" YELLOW="" CYAN="" MAGENTA="" RESET=""
    RL_S="" RL_E=""
  else
    BOLD=$'\e[1m'      DIM=$'\e[2m'
    RED=$'\e[1;31m'    GREEN=$'\e[1;32m'  YELLOW=$'\e[1;33m'
    MAGENTA=$'\e[1;35m' CYAN=$'\e[1;36m'
    RESET=$'\e[0m'
    # Readline's non-printing markers. A `read -e` prompt must wrap its escape
    # sequences in these or readline counts them as visible characters and puts
    # the cursor in the wrong column as soon as a line is recalled or edited.
    RL_S=$'\001' RL_E=$'\002'
  fi
}

# All banner/prompt/summary "chrome" goes to stderr so that stdout carries
# only the per-path results and stays pipe-friendly.
emsg() { printf '%s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Big, friendly title with a description underneath it.
# ---------------------------------------------------------------------------
print_banner() {
  local rule
  rule=$(printf '%.0s━' {1..64})
  {
    printf '\n%s%s%s\n' "$CYAN" "$rule" "$RESET"
    printf '%s%s\n' "$BOLD$MAGENTA" "$RESET"
    # figlet "standard" rendering of "dirPathPerms" (embedded; no runtime dep)
    printf '%s' "$BOLD$CYAN"
    cat <<'BANNER'
     _ _      ____       _   _     ____
  __| (_)_ __|  _ \ __ _| |_| |__ |  _ \ ___ _ __ _ __ ___  ___
 / _` | | '__| |_) / _` | __| '_ \| |_) / _ \ '__| '_ ` _ \/ __|
| (_| | | |  |  __/ (_| | |_| | | |  __/  __/ |  | | | | | \__ \
 \__,_|_|_|  |_|   \__,_|\__|_| |_|_|   \___|_|  |_| |_| |_|___/
BANNER
    printf '%s' "$RESET"
    printf '  %sFile & Directory Permission Checker%s   %sv%s%s\n' \
      "$BOLD" "$RESET" "$DIM" "$VERSION" "$RESET"
    printf '  %sAudit whether read / write / execute is set for owner, group, or other.%s\n' \
      "$DIM" "$RESET"
    printf '%s%s%s\n\n' "$CYAN" "$rule" "$RESET"
  } >&2
}

usage() {
  cat >&2 <<USAGE
${BOLD}dirPathPerms${RESET} ${DIM}v${VERSION}${RESET} — file & directory permission checker

${BOLD}USAGE${RESET}
  dirPathPerms.sh [OPTIONS] [PATH|FILE]

Checks the paths you name directly, or every path listed in an input file.
A bare argument is read as a list of paths when it is a regular file, and
checked directly when it is a directory.

Runs interactively when a required value is missing and a terminal is
attached; runs non-interactively when everything is supplied via flags.

${BOLD}OPTIONS${RESET}
  -P, --path PATH     Check PATH directly. Repeatable. Use this instead of
                      --file when you just want to check one or more paths.
  -f, --file FILE     Input file: one absolute path per line. Blank lines and
                      lines starting with '#' are ignored.
  -w, --who WHO       Whose permission to check: owner|group|other
                      (aliases: u|g|o).
  -p, --perm PERM     Permission to check: read|write|execute (aliases: r|w|x).
  -a, --all           Check owner, group AND other at once (permission matrix).
      --no-color      Disable colored output.
  -h, --help          Show this help and exit.
  -V, --version       Print the version and exit.

${BOLD}EXAMPLES${RESET}
  # Fully interactive (prompts for the path, who, and permission)
  dirPathPerms.sh

  # Check one path directly
  dirPathPerms.sh --path ~/Documents --who owner --perm read

  # A bare path works the same way
  dirPathPerms.sh -w owner -p r ~/Documents

  # Several paths at once
  dirPathPerms.sh -P /etc/passwd -P /var/log -w group -p w

  # Non-interactive: does the group have write on every listed path?
  dirPathPerms.sh --file paths.txt --who group --perm write

  # Show read access for owner/group/other across all paths, no colors
  dirPathPerms.sh -a -p r -f paths.txt --no-color

${BOLD}INPUT FILE FORMAT${RESET}
  /etc/passwd
  ~/report.log
  # comments and blank lines are skipped
  /var/www
USAGE
}

# ---------------------------------------------------------------------------
# Small helpers.
# ---------------------------------------------------------------------------
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Wrap prose to ~80 columns (kept from the original UX, minus the name clash
# with the system `fold` command).
wrap_text() {
  local c=0 word wrapped="" line
  while IFS= read -r line; do
    for word in $line; do
      c=$((c + ${#word} + 1))
      if [[ $c -gt 80 ]]; then
        printf '%s\n' "$wrapped"
        c=${#word}
        wrapped=""
      fi
      wrapped="$wrapped $word"
    done
    printf '%s\n' "$wrapped"
    c=0
    wrapped=""
  done
}

# Portable 10-char mode string (e.g. -rwxr-xr-x). GNU coreutils first, then
# BSD/macOS. Prints nothing and returns non-zero if the path can't be stat'd.
mode_string() {
  stat -c '%A' "$1" 2>/dev/null || stat -f '%Sp' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Path normalization.
#
# A line in the input file is typed by a human or pasted out of a file manager,
# so it is frequently not a bare literal path. It arrives wrapped in quotes,
# with a leading `~`, with a `$VAR` in it, with backslash-escaped spaces (what
# dragging a file from Finder into a terminal produces), with stray
# indentation, or with a CRLF tail. Each of those was previously looked up
# verbatim and written off as "path does not exist".
#
# Expansion is hand-rolled rather than delegated to `eval` on purpose: an input
# file must only ever be able to name files, never run commands, so `$(...)`
# and backticks are deliberately left as literal text.
# ---------------------------------------------------------------------------

# The helpers below return through this global rather than on stdout. They run
# once per input line, and command substitution would fork a subshell each time.
NORM_PATH=""

# Drop a CRLF tail and any surrounding whitespace.
trim_ws() {
  local s="${1%$'\r'}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  NORM_PATH="$s"
}

# Home directory of a username. Linux keeps local accounts in the passwd
# database; macOS keeps them in Directory Services, where getent does not exist.
# The lookups read from /dev/null because this runs inside the loop that has the
# input file on stdin, and a helper that read from it would eat the paths.
home_of() {
  local u="$1" h=""
  if command -v getent >/dev/null 2>&1; then
    h=$(getent passwd "$u" 2>/dev/null </dev/null | cut -d: -f6)
  fi
  if [[ -z "$h" ]] && command -v dscl >/dev/null 2>&1; then
    h=$(dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null </dev/null)
    h="${h#NFSHomeDirectory: }"
    # dscl falls back to a multi-line form for values it cannot inline; there
    # is no home directory to be had in that case.
    case "$h" in *$'\n'*) h="" ;; esac
  fi
  NORM_PATH="$h"
}

# Substitute $VAR and ${VAR} from the environment. Only well-formed identifiers
# are substituted, which is what keeps `$(id -un)` and `$1` literal.
expand_vars() {
  local s="$1" out="" head name
  case "$s" in *'$'*) ;; *) NORM_PATH="$s"; return ;; esac
  while [[ -n "$s" ]]; do
    head="${s%%\$*}"
    if [[ "$head" == "$s" ]]; then
      out="$out$s"
      break
    fi
    out="$out$head"
    s="${s#"$head"}"
    if [[ "$s" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\} ]]; then
      name="${BASH_REMATCH[1]}"
      out="$out${!name-}"
      s="${s:${#name}+3}"
    elif [[ "$s" =~ ^\$([A-Za-z_][A-Za-z0-9_]*) ]]; then
      name="${BASH_REMATCH[1]}"
      out="$out${!name-}"
      s="${s:${#name}+1}"
    else
      out="$out\$"
      s="${s:1}"
    fi
  done
  NORM_PATH="$out"
}

# Turn each backslash escape into the character it stands for, so that
# `my\ file` becomes `my file`.
unescape() {
  local s="$1" out="" c
  case "$s" in *\\*) ;; *) NORM_PATH="$s"; return ;; esac
  while [[ -n "$s" ]]; do
    c="${s:0:1}"
    if [[ "$c" == "\\" && ${#s} -gt 1 ]]; then
      out="$out${s:1:1}"
      s="${s:2}"
    else
      out="$out$c"
      s="${s:1}"
    fi
  done
  NORM_PATH="$out"
}

# Run one raw line through every normalization step, in a fixed order.
normalize_path() {
  local p rest user home

  trim_ws "$1"
  p="$NORM_PATH"

  # A single surrounding pair of quotes, as left behind by a copy out of a shell.
  if [[ ${#p} -ge 2 ]]; then
    case "$p" in
      \"*\" | \'*\') p="${p:1:${#p}-2}" ;;
    esac
  fi

  # A leading tilde, expanded the way a shell would: ~, ~/path, ~user, ~user/path.
  # The tildes below are data being matched, not paths to be expanded by this
  # shell, which is exactly what SC2088 warns about.
  # shellcheck disable=SC2088
  case "$p" in
    '~')   p="$HOME" ;;
    '~/'*) p="$HOME/${p#\~/}" ;;
    '~'*)
      rest="${p#\~}"
      user="${rest%%/*}"
      if [[ "$user" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
        home_of "$user"
        home="$NORM_PATH"
        if [[ -n "$home" ]]; then
          case "$rest" in
            */*) p="$home/${rest#*/}" ;;
            *)   p="$home" ;;
          esac
        fi
      fi
      ;;
  esac

  expand_vars "$p"
  unescape "$NORM_PATH"
}

# Resolve one raw line to the path that should be checked. Normalization is a
# convenience, so when the normalized form does not exist but the raw line
# does, the raw line wins: a file whose name genuinely contains a tilde, dollar
# sign, quote, or backslash is still checked exactly as it was written.
resolve_path() {
  local raw="$1" norm
  normalize_path "$raw"
  norm="$NORM_PATH"
  if [[ ! -e "$norm" && -e "$raw" ]]; then
    NORM_PATH="$raw"
  fi
}

# ---------------------------------------------------------------------------
# Input normalization / validation.
# ---------------------------------------------------------------------------
who=""       # u | g | o | all
who_text=""
normalize_who() {
  case "$(lc "$1")" in
    owner|u|user) who="u"; who_text="Owner" ;;
    group|g)      who="g"; who_text="Group" ;;
    other|o)      who="o"; who_text="Other" ;;
    all|a)        who="all"; who_text="All" ;;
    *) return 1 ;;
  esac
}

perm=""      # r | w | x
perm_text=""
normalize_perm() {
  case "$(lc "$1")" in
    read|r)         perm="r"; perm_text="read" ;;
    write|w)        perm="w"; perm_text="write" ;;
    execute|exec|x) perm="x"; perm_text="execute" ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Interactive prompts (used only for values not supplied on the command line).
# ---------------------------------------------------------------------------
prompt_file() {
  # Arrow-key recall needs the history list, which a non-interactive shell
  # leaves switched off. HISTFILE is cleared so a run can never write back to
  # the user's own shell history.
  set -o history 2>/dev/null || true
  unset HISTFILE

  emsg ""
  emsg "Enter ${BOLD}either${RESET} a path to check ${BOLD}or${RESET} a file listing paths to check:"
  emsg ""
  emsg "  ~/Documents                  a path — checked directly"
  emsg "  /location/of/myPaths.txt     a text file, one path per line"
  emsg ""
  wrap_text >&2 <<< "Absolute paths are required if the script runs from another location. A leading ~ and any \$VAR are expanded for you. Use the up and down arrows to recall anything you have already typed this session."

  local reply candidate
  while true; do
    if ! read -e -p "${RL_S}${BOLD}${RL_E}Path or list file:${RL_S}${RESET}${RL_E} " -r reply; then
      emsg ""
      exit 2
    fi
    [[ -n "$reply" ]] && history -s "$reply"

    resolve_path "$reply"
    candidate="$NORM_PATH"

    # A regular file is read as a list of paths, which is this tool's original
    # mode. A directory cannot be a list, so it is the path to check itself.
    if [[ -f "$candidate" ]]; then
      file_path="$candidate"
      return
    fi
    if [[ -e "$candidate" ]]; then
      direct_paths=("$candidate")
      return
    fi

    emsg ""
    if [[ -z "$candidate" ]]; then
      emsg "${RED}Nothing entered.${RESET} Type a path, or Ctrl-C to quit."
    else
      emsg "${RED}No such path:${RESET} $candidate"
    fi
  done
}

prompt_who() {
  while true; do
    emsg ""
    printf '%sCheck permissions for (O)wner, (G)roup, Oth(e)r, or (A)ll?%s ' \
      "$BOLD" "$RESET" >&2
    read -r reply
    if normalize_who "$reply"; then
      break
    fi
    emsg "${RED}Invalid choice.${RESET} Enter O, G, E, or A."
  done
}

prompt_perm() {
  while true; do
    emsg ""
    printf '%sCheck for (R)ead, (W)rite, or e(X)ecute permission?%s ' \
      "$BOLD" "$RESET" >&2
    read -r reply
    if normalize_perm "$reply"; then
      break
    fi
    emsg "${RED}Invalid choice.${RESET} Enter R, W, or X."
  done
}

# ---------------------------------------------------------------------------
# Does the 3-char class field (e.g. "rwx" or "r-x") grant $perm?
# ---------------------------------------------------------------------------
has_perm() { [[ "$1" == *"$perm"* ]]; }

# ---------------------------------------------------------------------------
# The check loop.
# ---------------------------------------------------------------------------
granted=0
denied=0
skipped=0
total=0

# Check one raw entry — a line from the input file, or a --path value — and
# print its verdict. Tallies land in the counters above.
check_one_raw() {
  local path perms owner_perm group_perm other_perm current
  local badge_u badge_g badge_o

  resolve_path "$1"
  path="$NORM_PATH"

  if [[ ! -e "$path" ]]; then
    printf '%s  %-44s  SKIP (path does not exist)%s\n' \
      "$YELLOW" "$path" "$RESET"
    skipped=$((skipped + 1))
    return
  fi

  perms=$(mode_string "$path")
  if [[ -z "$perms" ]]; then
    printf '%s  %-44s  SKIP (could not read mode)%s\n' \
      "$YELLOW" "$path" "$RESET"
    skipped=$((skipped + 1))
    return
  fi

  owner_perm=${perms:1:3}
  group_perm=${perms:4:3}
  other_perm=${perms:7:3}
  total=$((total + 1))

  if [[ "$who" == "all" ]]; then
    # Permission matrix: show the requested permission per class.
    if has_perm "$owner_perm"; then badge_u="${GREEN}u+${RESET}"; granted=$((granted + 1)); else badge_u="${RED}u-${RESET}"; fi
    if has_perm "$group_perm"; then badge_g="${GREEN}g+${RESET}"; granted=$((granted + 1)); else badge_g="${RED}g-${RESET}"; fi
    if has_perm "$other_perm"; then badge_o="${GREEN}o+${RESET}"; granted=$((granted + 1)); else badge_o="${RED}o-${RESET}"; fi
    printf '  %-44s  %s %s %s   %s[%s %s %s]%s\n' \
      "$path" "$badge_u" "$badge_g" "$badge_o" \
      "$DIM" "$owner_perm" "$group_perm" "$other_perm" "$RESET"
    return
  fi

  case "$who" in
    u) current=$owner_perm ;;
    g) current=$group_perm ;;
    o) current=$other_perm ;;
  esac

  if has_perm "$current"; then
    printf '%s  %-44s  YES%s   %s[owner %s | group %s | other %s]%s\n' \
      "$GREEN" "$path" "$RESET" \
      "$DIM" "$owner_perm" "$group_perm" "$other_perm" "$RESET"
    granted=$((granted + 1))
  else
    printf '%s  %-44s  NO  (no %s for %s)%s   %s[owner %s | group %s | other %s]%s\n' \
      "$RED" "$path" "$perm_text" "$who_text" "$RESET" \
      "$DIM" "$owner_perm" "$group_perm" "$other_perm" "$RESET"
    denied=$((denied + 1))
  fi
}

# ---------------------------------------------------------------------------
# The check loop. Entries come either from --path values or from the input
# file, never both.
# ---------------------------------------------------------------------------
run_checks() {
  local line source_label

  if [[ ${#direct_paths[@]} -eq 1 ]]; then
    resolve_path "${direct_paths[0]}"
    source_label="$NORM_PATH"
  elif [[ ${#direct_paths[@]} -gt 1 ]]; then
    source_label="${#direct_paths[@]} paths given"
  else
    source_label="from ${file_path}"
  fi

  emsg "${BOLD}Checking ${perm_text} permission for ${who_text}${RESET} — ${source_label}"
  emsg ""

  if [[ ${#direct_paths[@]} -gt 0 ]]; then
    for line in ${direct_paths[@]+"${direct_paths[@]}"}; do
      check_one_raw "$line"
    done
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Trim before testing for blanks and comments: a CRLF file would
      # otherwise turn every blank line into a bogus path, and an indented
      # comment would be treated as one too.
      trim_ws "$line"
      line="$NORM_PATH"
      case "$line" in
        '' | '#'*) continue ;;
      esac
      check_one_raw "$line"
    done < "$file_path"
  fi

  emsg ""
  if [[ "$who" == "all" ]]; then
    emsg "${BOLD}Summary:${RESET} ${total} path(s) checked, ${skipped} skipped — ${GREEN}${granted}${RESET} class-grants of ${perm_text}."
  else
    emsg "${BOLD}Summary:${RESET} ${GREEN}${granted} granted${RESET}, ${RED}${denied} denied${RESET}, ${YELLOW}${skipped} skipped${RESET} (${total} checked)."
  fi
}

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
file_path=""
direct_paths=()
main() {
  local positional="" candidate
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file)
        [[ $# -ge 2 ]] || { setup_colors; emsg "Option $1 requires a value."; exit 2; }
        file_path="$2"; shift 2 ;;
      -P|--path)
        [[ $# -ge 2 ]] || { setup_colors; emsg "Option $1 requires a value."; exit 2; }
        direct_paths+=("$2"); shift 2 ;;
      -w|--who)
        [[ $# -ge 2 ]] || { setup_colors; emsg "Option $1 requires a value."; exit 2; }
        if ! normalize_who "$2"; then setup_colors; emsg "Invalid --who value: $2 (use owner|group|other|all)."; exit 2; fi
        shift 2 ;;
      -p|--perm)
        [[ $# -ge 2 ]] || { setup_colors; emsg "Option $1 requires a value."; exit 2; }
        if ! normalize_perm "$2"; then setup_colors; emsg "Invalid --perm value: $2 (use read|write|execute)."; exit 2; fi
        shift 2 ;;
      -a|--all)      who="all"; who_text="All"; shift ;;
      --no-color)    USE_COLOR="no"; shift ;;
      -h|--help)     setup_colors; usage; exit 0 ;;
      -V|--version)  printf 'dirPathPerms %s\n' "$VERSION"; exit 0 ;;
      --)            shift; [[ $# -gt 0 ]] && positional="$1"; break ;;
      -*)            setup_colors; emsg "Unknown option: $1"; usage; exit 2 ;;
      *)
        if [[ -z "$positional" ]]; then positional="$1"; else
          setup_colors; emsg "Unexpected argument: $1"; exit 2
        fi
        shift ;;
    esac
  done

  setup_colors
  print_banner

  if [[ -n "$file_path" && ${#direct_paths[@]} -gt 0 ]]; then
    emsg "${RED}--file and --path cannot be combined.${RESET}"
    emsg "--file reads a list of paths; --path names the paths itself."
    exit 2
  fi

  # A bare argument is whichever it turns out to be: a regular file is read as
  # a list of paths, and anything else that exists is a path to check.
  if [[ -z "$file_path" && ${#direct_paths[@]} -eq 0 && -n "$positional" ]]; then
    resolve_path "$positional"
    candidate="$NORM_PATH"
    if [[ -f "$candidate" ]]; then
      file_path="$candidate"
    elif [[ -e "$candidate" ]]; then
      direct_paths=("$candidate")
    else
      emsg "${RED}No such path:${RESET} $candidate"; exit 2
    fi
  fi

  # Fill in whatever wasn't provided on the command line. Prompt only when a
  # terminal is attached; otherwise fail clearly (non-interactive contract).
  if [[ -z "$file_path" && ${#direct_paths[@]} -eq 0 ]]; then
    if [[ -t 0 ]]; then prompt_file
    else emsg "${RED}Nothing to check.${RESET} Pass --path PATH or --file FILE (see --help)."; exit 2; fi
  elif [[ -n "$file_path" ]]; then
    # A quoted --file value reaches us unexpanded (e.g. --file '~/paths.txt'),
    # so the input file gets the same treatment as the paths listed inside it.
    resolve_path "$file_path"
    file_path="$NORM_PATH"
    if [[ ! -f "$file_path" ]]; then
      # Say what is actually wrong. Reporting "file not found" for a directory
      # that plainly exists sends people hunting for the wrong problem.
      if [[ -d "$file_path" ]]; then
        emsg "${RED}Error:${RESET} $file_path is a directory, not a list of paths."
        emsg "To check it directly, use: ${BOLD}--path $file_path${RESET}"
      elif [[ -e "$file_path" ]]; then
        emsg "${RED}Error:${RESET} $file_path is not a regular file, so it cannot be read as a list of paths."
        emsg "To check it directly, use: ${BOLD}--path $file_path${RESET}"
      else
        emsg "${RED}Error: no such file:${RESET} $file_path"
      fi
      exit 2
    fi
  fi

  if [[ -z "$who" ]]; then
    if [[ -t 0 ]]; then prompt_who
    else emsg "${RED}No target given.${RESET} Pass --who owner|group|other|all (see --help)."; exit 2; fi
  fi

  if [[ -z "$perm" ]]; then
    if [[ -t 0 ]]; then prompt_perm
    else emsg "${RED}No permission given.${RESET} Pass --perm read|write|execute (see --help)."; exit 2; fi
  fi

  run_checks
}

main "$@"
