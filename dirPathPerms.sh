#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
## Author: Tito Valentin
## Name of Program: dirPathPerms.sh
## Date Created: 2026-07-13
## Description: Interactive and non-interactive checker that reports whether a
##              chosen permission (read/write/execute) is set for the owner,
##              group, or other on every path listed in an input file.

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
  else
    BOLD=$'\e[1m'      DIM=$'\e[2m'
    RED=$'\e[1;31m'    GREEN=$'\e[1;32m'  YELLOW=$'\e[1;33m'
    MAGENTA=$'\e[1;35m' CYAN=$'\e[1;36m'
    RESET=$'\e[0m'
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
  dirPathPerms.sh [OPTIONS] [FILE]

Runs interactively when a required value is missing and a terminal is
attached; runs non-interactively when everything is supplied via flags.

${BOLD}OPTIONS${RESET}
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
  # Fully interactive (prompts for file, who, and permission)
  dirPathPerms.sh

  # Non-interactive: does the group have write on every listed path?
  dirPathPerms.sh --file paths.txt --who group --perm write

  # Show read access for owner/group/other across all paths, no colors
  dirPathPerms.sh -a -p r -f paths.txt --no-color

${BOLD}INPUT FILE FORMAT${RESET}
  /etc/passwd
  /home/user/report.log
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
  emsg ""
  emsg "Example file format (one absolute path per line):"
  emsg ""
  emsg "  /location/of/dirname1"
  emsg "  /location/of/filename1"
  emsg ""
  wrap_text >&2 <<< "Enter the path to the file listing the directories or files to check. Absolute paths are required if the script runs from another location."
  while true; do
    printf '%s' "${BOLD}File path:${RESET} " >&2
    read -r file_path
    if [[ -f "$file_path" ]]; then
      break
    fi
    emsg ""
    emsg "${RED}Error: file not found.${RESET} Please try again."
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
run_checks() {
  local granted=0 denied=0 skipped=0 total=0
  local line path perms owner_perm group_perm other_perm current
  local badge_u badge_g badge_o

  emsg "${BOLD}Checking ${perm_text} permission for ${who_text}${RESET} — from ${file_path}"
  emsg ""

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blanks and comments.
    case "$line" in
      '' | '#'*) continue ;;
    esac
    path="$line"

    if [[ ! -e "$path" ]]; then
      printf '%s  %-44s  SKIP (path does not exist)%s\n' \
        "$YELLOW" "$path" "$RESET"
      skipped=$((skipped + 1))
      continue
    fi

    perms=$(mode_string "$path")
    if [[ -z "$perms" ]]; then
      printf '%s  %-44s  SKIP (could not read mode)%s\n' \
        "$YELLOW" "$path" "$RESET"
      skipped=$((skipped + 1))
      continue
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
      continue
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
  done < "$file_path"

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
main() {
  local positional=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file)
        [[ $# -ge 2 ]] || { setup_colors; emsg "Option $1 requires a value."; exit 2; }
        file_path="$2"; shift 2 ;;
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

  [[ -z "$file_path" && -n "$positional" ]] && file_path="$positional"

  setup_colors
  print_banner

  # Fill in whatever wasn't provided on the command line. Prompt only when a
  # terminal is attached; otherwise fail clearly (non-interactive contract).
  if [[ -z "$file_path" ]]; then
    if [[ -t 0 ]]; then prompt_file
    else emsg "${RED}No input file given.${RESET} Pass --file FILE (see --help)."; exit 2; fi
  elif [[ ! -f "$file_path" ]]; then
    emsg "${RED}Error: file not found:${RESET} $file_path"; exit 2
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
