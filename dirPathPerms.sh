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
    STRIPE="" FG_RESET="" ROW_END=""
  else
    BOLD=$'\e[1m'      DIM=$'\e[2m'
    RED=$'\e[1;31m'    GREEN=$'\e[1;32m'  YELLOW=$'\e[1;33m'
    MAGENTA=$'\e[1;35m' CYAN=$'\e[1;36m'
    RESET=$'\e[0m'
    # Zebra striping for the results table. A row sets STRIPE once and closes
    # with ROW_END; anything colored inside it must return to the default
    # foreground with FG_RESET rather than RESET, which would also drop the
    # row's background colour partway along the line.
    STRIPE=$'\e[48;5;236m'
    FG_RESET=$'\e[22;39m'
    ROW_END=$'\e[0m'
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
A bare argument is read as a list of paths when it looks like one (its first
meaningful line is a path); otherwise it is the path to check.

With no arguments it runs as a session: it keeps asking for paths, with
arrow-key recall, until you press q. Runs non-interactively, checking once
and exiting, when everything is supplied via flags.

Results are printed as a table of one row per path.

${BOLD}OPTIONS${RESET}
  -P, --path PATH     Check PATH directly. Repeatable. Use this instead of
                      --file when you just want to check one or more paths.
  -f, --file FILE     Input file: one absolute path per line. Blank lines and
                      lines starting with '#' are ignored.
  -w, --who WHO       Whose permission to check: owner|group|other
                      (aliases: u|g|o).
  -p, --perm PERM     Permission to check: read|write|execute|all
                      (aliases: r|w|x|a). 'all' checks read, write and execute
                      together.
  -a, --all           Check owner, group AND other at once (permission matrix).
      --no-color      Disable colored output.
  -h, --help          Show this help and exit.
  -V, --version       Print the version and exit.

${BOLD}EXAMPLES${RESET}
  # Interactive session: asks for paths until you press q
  dirPathPerms.sh

  # Check one path directly
  dirPathPerms.sh --path ~/Documents --who owner --perm read

  # The full picture: every permission, for every class
  dirPathPerms.sh --path ~/Documents --all --perm all

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

# A regular file given where a path was expected is ambiguous: it may be the
# path to check, or a file listing paths to check. Decide by reading it. A list
# of paths contains paths, so its first meaningful line starts with /, ~ or $.
# Anything else — /etc/passwd, a binary, prose — is the path to check itself.
# Only --file forces the list reading unconditionally.
looks_like_path_list() {
  local line seen=0
  [[ -s "$1" ]] || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    trim_ws "$line"
    line="$NORM_PATH"
    # The tilde below is a literal being matched, not a path for this shell to
    # expand, which is what SC2088 warns about.
    # shellcheck disable=SC2088
    case "$line" in
      '' | '#'*) ;;
      /* | '~'* | '$'*) return 0 ;;
      *) return 1 ;;
    esac
    # Give up rather than read a whole binary looking for a path.
    seen=$((seen + 1))
    (( seen > 20 )) && return 1
  done < "$1"
  return 1
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

perm=""      # r | w | x | all
perm_text=""
normalize_perm() {
  case "$(lc "$1")" in
    read|r)         perm="r"; perm_text="read" ;;
    write|w)        perm="w"; perm_text="write" ;;
    execute|exec|x) perm="x"; perm_text="execute" ;;
    all|a)          perm="all"; perm_text="read/write/execute" ;;
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
  wrap_text >&2 <<< "Absolute paths are required if the script runs from another location. A leading ~ and any \$VAR are expanded for you. Use the up and down arrows to recall anything you have already typed this session, and press q to quit."

  prompt_next
}

# Ask for one path or list file. Returns 1 when the user asks to quit, which
# ends the session rather than the whole script.
prompt_next() {
  local reply candidate

  # Each round replaces the previous entry rather than adding to it.
  file_path=""
  direct_paths=()

  while true; do
    if ! read -e -p "${RL_S}${BOLD}${RL_E}Path or list file${RL_S}${DIM}${RL_E} (q to quit)${RL_S}${RESET}${BOLD}${RL_E}:${RL_S}${RESET}${RL_E} " -r reply; then
      # Ctrl-D reads as end of input, which means the same thing as q.
      emsg ""
      return 1
    fi

    case "$(lc "$reply")" in
      q | quit | exit) return 1 ;;
    esac

    [[ -n "$reply" ]] && history -s "$reply"

    resolve_path "$reply"
    candidate="$NORM_PATH"

    if [[ -f "$candidate" ]]; then
      if looks_like_path_list "$candidate"; then
        file_path="$candidate"
      else
        direct_paths=("$candidate")
      fi
      return 0
    fi
    if [[ -e "$candidate" ]]; then
      direct_paths=("$candidate")
      return 0
    fi

    emsg ""
    if [[ -z "$candidate" ]]; then
      emsg "${RED}Nothing entered.${RESET} Type a path, or q to quit."
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
    printf '%sCheck for (R)ead, (W)rite, e(X)ecute, or (A)ll permissions?%s ' \
      "$BOLD" "$RESET" >&2
    read -r reply
    if normalize_perm "$reply"; then
      break
    fi
    emsg "${RED}Invalid choice.${RESET} Enter R, W, X, or A."
  done
}

# ---------------------------------------------------------------------------
# Does the 3-char class field (e.g. "rwx" or "r-x") grant permission $2?
# ---------------------------------------------------------------------------
has_perm() { [[ "$1" == *"$2"* ]]; }

# The 3-char field a class owns within a 10-char mode string.
class_field() {
  case "$2" in
    u) printf '%s' "${1:1:3}" ;;
    g) printf '%s' "${1:4:3}" ;;
    o) printf '%s' "${1:7:3}" ;;
  esac
}

class_label() {
  case "$1" in
    u) printf 'Owner' ;;
    g) printf 'Group' ;;
    o) printf 'Other' ;;
  esac
}

# ---------------------------------------------------------------------------
# Results for the current table. Parallel arrays, one entry per checked path.
# Checking and rendering are kept apart so that the table can size its columns
# to the widest value it is about to print.
# ---------------------------------------------------------------------------
ROW_PATH=()
ROW_MODE=()   # 10-char mode string, empty when there is nothing to report
ROW_NOTE=()   # why a row has no mode

reset_rows() { ROW_PATH=(); ROW_MODE=(); ROW_NOTE=(); }

# Resolve one raw entry and record what was found.
record_path() {
  local path mode
  resolve_path "$1"
  path="$NORM_PATH"

  if [[ ! -e "$path" ]]; then
    ROW_PATH+=("$path"); ROW_MODE+=(""); ROW_NOTE+=("does not exist")
    return
  fi
  mode=$(mode_string "$path")
  if [[ -z "$mode" ]]; then
    ROW_PATH+=("$path"); ROW_MODE+=(""); ROW_NOTE+=("mode unreadable")
    return
  fi
  ROW_PATH+=("$path"); ROW_MODE+=("$mode"); ROW_NOTE+=("")
}

# Which classes and permissions get columns.
display_classes=()
display_perms=()
setup_columns() {
  if [[ "$who" == "all" ]]; then display_classes=(u g o); else display_classes=("$who"); fi
  if [[ "$perm" == "all" ]]; then display_perms=(r w x); else display_perms=("$perm"); fi
}

# ---------------------------------------------------------------------------
# Table rendering.
# ---------------------------------------------------------------------------

# A run of $2 copies of $1, built without a loop.
hbar() {
  local s
  printf -v s '%*s' "$2" ''
  printf '%s' "${s// /$1}"
}

# $1 centered within $3 columns, where $2 is how many columns $1 occupies on
# screen. The width is passed in rather than measured because ${#s} counts bytes
# outside a UTF-8 locale, which would silently skew every border once a
# multi-byte glyph appears in a cell.
center_w() {
  local text="$1" cols="$2" width="$3" pad_l pad_r
  if (( cols >= width )); then printf '%s' "$text"; return; fi
  pad_l=$(( (width - cols) / 2 ))
  pad_r=$(( width - cols - pad_l ))
  printf '%*s%s%*s' "$pad_l" '' "$text" "$pad_r" ''
}

# $1 centered within $2 columns. ASCII only — see center_w.
center() { center_w "$1" "${#1}" "$2"; }

# Render every recorded row as a bordered table with headers. Adjacent rows get
# alternating backgrounds so that a long list stays readable.
render_table() {
  local n=${#ROW_PATH[@]}
  local pathw=4 modew=4 classw i s c p
  local mode field cell stripe

  (( n == 0 )) && return

  for (( i = 0; i < n; i++ )); do
    s="${ROW_PATH[$i]}"
    (( ${#s} > pathw )) && pathw=${#s}
    s="${ROW_MODE[$i]}"
    [[ -z "$s" ]] && s="${ROW_NOTE[$i]}"
    (( ${#s} > modew )) && modew=${#s}
  done

  # One cell per class, or three when every permission is being shown.
  if [[ "$perm" == "all" ]]; then classw=13; else classw=7; fi

  # ── borders ──
  rule() {
    local left="$1" mid="$2" right="$3" out
    out="$left$(hbar '─' $((pathw + 2)))"
    for c in ${display_classes[@]+"${display_classes[@]}"}; do
      out="$out$mid$(hbar '─' "$classw")"
    done
    out="$out$mid$(hbar '─' $((modew + 2)))$right"
    printf '%s\n' "$out"
  }

  rule '┌' '┬' '┐'

  # ── header ──
  # With every permission shown, the class name spans its three cells and a
  # second header row names them.
  if [[ "$perm" == "all" ]]; then
    s="│ $(center '' "$pathw") │"
    for c in ${display_classes[@]+"${display_classes[@]}"}; do
      s="$s$(center "$(class_label "$c")" "$classw")│"
    done
    s="$s$(center '' $((modew + 2)))│"
    printf '%s%s%s\n' "$BOLD" "$s" "$RESET"
  fi

  s="│ $(printf '%-*s' "$pathw" 'Path') │"
  for c in ${display_classes[@]+"${display_classes[@]}"}; do
    if [[ "$perm" == "all" ]]; then
      s="$s$(center 'R   W   X' "$classw")│"
    else
      s="$s$(center "$(class_label "$c")" "$classw")│"
    fi
  done
  s="$s $(printf '%-*s' "$modew" 'Mode') │"
  printf '%s%s%s\n' "$BOLD" "$s" "$RESET"

  rule '├' '┼' '┤'

  # ── rows ──
  for (( i = 0; i < n; i++ )); do
    # Alternate the background so neighbouring rows never look alike.
    if (( i % 2 == 1 )); then stripe="$STRIPE"; else stripe=""; fi
    mode="${ROW_MODE[$i]}"

    printf '%s' "$stripe"
    printf '│ %-*s │' "$pathw" "${ROW_PATH[$i]}"

    for c in ${display_classes[@]+"${display_classes[@]}"}; do
      if [[ -z "$mode" ]]; then
        # Nothing was readable, so no cell can claim anything.
        printf '%s%s%s│' "$DIM" "$(center_w '—' 1 "$classw")" "$FG_RESET"
        continue
      fi
      field=$(class_field "$mode" "$c")
      if [[ "$perm" == "all" ]]; then
        # Built with literal spacing rather than centered, so the glyphs line up
        # under the R/W/X header without depending on how wide the shell thinks
        # a check mark is.
        cell=""
        for p in ${display_perms[@]+"${display_perms[@]}"}; do
          [[ -n "$cell" ]] && cell="$cell   "
          if has_perm "$field" "$p"; then
            cell="$cell${GREEN}✓${FG_RESET}"
          else
            cell="$cell${DIM}·${FG_RESET}"
          fi
        done
        printf '  %s  │' "$cell"
      else
        if has_perm "$field" "$perm"; then
          printf '%s%s%s│' "$GREEN" "$(center 'YES' "$classw")" "$FG_RESET"
        else
          printf '%s%s%s│' "$RED" "$(center 'NO' "$classw")" "$FG_RESET"
        fi
      fi
    done

    if [[ -n "$mode" ]]; then
      printf ' %s%-*s%s │' "$DIM" "$modew" "$mode" "$FG_RESET"
    else
      printf ' %s%-*s%s │' "$YELLOW" "$modew" "${ROW_NOTE[$i]}" "$FG_RESET"
    fi
    printf '%s\n' "$ROW_END"
  done

  rule '└' '┴' '┘'
}

# The tally under the table.
render_summary() {
  local n=${#ROW_PATH[@]}
  local i c p mode field
  local checked=0 skipped=0 cells=0 granted=0 denied=0

  for (( i = 0; i < n; i++ )); do
    mode="${ROW_MODE[$i]}"
    if [[ -z "$mode" ]]; then skipped=$((skipped + 1)); continue; fi
    checked=$((checked + 1))
    for c in ${display_classes[@]+"${display_classes[@]}"}; do
      field=$(class_field "$mode" "$c")
      for p in ${display_perms[@]+"${display_perms[@]}"}; do
        cells=$((cells + 1))
        if has_perm "$field" "$p"; then granted=$((granted + 1)); else denied=$((denied + 1)); fi
      done
    done
  done

  emsg ""
  if (( ${#display_classes[@]} == 1 && ${#display_perms[@]} == 1 )); then
    emsg "${BOLD}Summary:${RESET} ${GREEN}${granted} granted${RESET}, ${RED}${denied} denied${RESET}, ${YELLOW}${skipped} skipped${RESET} (${checked} checked)."
  else
    emsg "${BOLD}Summary:${RESET} ${checked} path(s) checked, ${YELLOW}${skipped} skipped${RESET} — ${GREEN}${granted}${RESET} of ${cells} permission checks granted."
  fi
}

# ---------------------------------------------------------------------------
# The check loop. Entries come either from --path values or from the input
# file, never both.
# ---------------------------------------------------------------------------
run_checks() {
  local line source_label

  reset_rows

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
      record_path "$line"
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
      record_path "$line"
    done < "$file_path"
  fi

  render_table
  render_summary
}

# ---------------------------------------------------------------------------
# Argument parsing.
# ---------------------------------------------------------------------------
file_path=""
direct_paths=()
session=0
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
        if ! normalize_perm "$2"; then setup_colors; emsg "Invalid --perm value: $2 (use read|write|execute|all)."; exit 2; fi
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

  # A bare argument is whichever it turns out to be: a file that reads like a
  # list of paths is one, and anything else that exists is a path to check.
  if [[ -z "$file_path" && ${#direct_paths[@]} -eq 0 && -n "$positional" ]]; then
    resolve_path "$positional"
    candidate="$NORM_PATH"
    if [[ -f "$candidate" ]] && looks_like_path_list "$candidate"; then
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
    if [[ -t 0 ]]; then
      # Nothing was named on the command line, so this is a session: keep
      # asking for paths until the user quits, rather than exiting after one.
      session=1
      prompt_file || { emsg "Nothing checked."; exit 0; }
    else
      emsg "${RED}Nothing to check.${RESET} Pass --path PATH or --file FILE (see --help)."; exit 2
    fi
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
    else emsg "${RED}No permission given.${RESET} Pass --perm read|write|execute|all (see --help)."; exit 2; fi
  fi

  setup_columns

  run_checks
  (( session == 0 )) && return 0

  # Same question, same who/perm — only the paths change.
  while prompt_next; do
    run_checks
  done
  emsg ""
  emsg "${DIM}Done.${RESET}"
}

main "$@"
