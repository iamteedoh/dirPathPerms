# dirPathPerms

[![CI](https://github.com/iamteedoh/dirPathPerms/actions/workflows/ci.yml/badge.svg)](https://github.com/iamteedoh/dirPathPerms/actions/workflows/ci.yml)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-%E2%9D%A4-ea4aaa?logo=githubsponsors)](https://github.com/sponsors/iamteedoh)
[![Patreon](https://img.shields.io/badge/Patreon-support-f96854?logo=patreon)](https://patreon.com/iamteedoh)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-ffdd00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/iamteedoh)

# File Permission Checker Script

## Overview

This Bash script checks specific file or directory permissions (Owner, Group, or Other; Read, Write, or Execute) for the paths you give it — either named directly, or listed one per line in an input file. Results come back as a color-coded table, one row per path.

It greets you with a big title banner and a short description, then runs in one
of two modes:

* **Interactively**, as a session: it asks for a path, shows the table, then
  asks for the next one — with tab completion and arrow-key history — until you
  press `q`.
* **Non-interactively** via command-line flags, checking once and exiting, which
  makes it easy to drop into scripts and CI.

When a required value is omitted and a terminal is attached, the script prompts
for it; when nothing is attached (a pipe or CI job), it fails fast with a clear
message instead of hanging.

<p align="center">
  <img src="assets/dirPathPerms_appThumbnail.png" alt="dirPathPerms banner and permission-check output" width="800">
</p>

## Use Case

This script is useful for:

* **System Auditing:** Quickly verifying if critical files or directories have the correct permissions set for specific users (owner, group members, others).
* **Configuration Management:** Ensuring that deployed files or directories match the intended permission policies.
* **Troubleshooting:** Diagnosing permission-related issues by checking specific access rights across multiple locations.
* **Security Checks:** Identifying potentially insecure permissions (e.g., world-writable files).

## Features

* **Title banner:** prints a big ASCII title and a one-line description each run.
* **Two run modes:** fully interactive prompts, or non-interactive with flags
  (`--path`/`--file`, `--who`, `--perm`) for scripting and CI.
* **Check a path directly** with `--path` (repeatable) or a bare argument — no
  need to author a list file just to check one directory.
* **Audit many paths at once** from an input file, one path per line.
* **Interactive session:** run it with no arguments and it keeps asking for
  paths until you press `q`, so checking ten paths does not mean launching it
  ten times.
* **Tab completion and history:** the prompt completes paths with `Tab`, recalls
  earlier entries with the up and down arrows, and supports the usual
  line-editing keys — so a typo does not mean retyping the whole path.
* **Results as a table:** one row per path, with headers and alternating row
  shading so adjacent rows stay easy to tell apart.
* Allows checking for Owner (`u`), Group (`g`), or Other (`o`) permissions, or
  **all three at once** with `--all`.
* Allows checking for Read (`r`), Write (`w`), or Execute (`x`) permissions, or
  **all three at once** with `--perm all`. Combine with `--all` for the full
  3×3 matrix of every permission against every class.
* Interactive prompts guide the user to choose what to check, and validate every
  choice.
* Clear, color-coded output:
    * **Green (`YES`)**: The specified permission is set.
    * **Red (`NO`)**: The specified permission is **not** set.
* A **summary line** with granted / denied / skipped counts, which switches to
  counting individual permission checks when a matrix is shown.
* A **`Mode` column** showing each path's actual mode (e.g. `-rw-r--r--`) for
  context, or why there is no result.
* **Comment & blank-line support:** lines in the input file that are empty or
  start with `#` are skipped, including indented ones.
* **Forgiving path input:** a leading `~`, a `$VAR`, surrounding quotes,
  backslash-escaped spaces, stray indentation, and Windows (CRLF) line endings
  are all handled, so a path pasted out of Finder or a terminal just works.
  Paths are only ever expanded, never executed.
* Gracefully handles and reports paths that do not exist, rather than failing the
  whole run.
* **Cross-platform:** works with both GNU (`stat -c`) and BSD/macOS (`stat -f`)
  `stat`, so no GNU coreutils install is required on macOS.
* Color is disabled automatically when output is piped or redirected, and can be
  turned off explicitly with `--no-color` (or the `NO_COLOR` environment variable).
* `--help` and `--version` flags.

## Prerequisites

* **Bash 3.2 or newer** — the version macOS still ships, so nothing needs
  installing there. Nothing in the script requires Bash 4+.
* Standard Unix/Linux command-line utilities, specifically:
    * `stat` for retrieving file permissions. The script auto-detects GNU
      (`stat -c '%A'`) and BSD/macOS (`stat -f '%Sp'`) variants, so it works on
      Linux and macOS out of the box — no GNU coreutils install required.
    * `read`, `printf`, `tr` (standard shell built-ins / utilities).
* Optional, and only for the extras:
    * A **terminal** for the interactive session — tab completion, history, and
      the prompts need one. Without a tty the script expects flags and exits
      rather than hanging.
    * `getent` (Linux) or `dscl` (macOS) to expand `~user` for *another* user.
      Your own `~` needs neither.

## Installation

It is a single self-contained script with no build step and no dependencies to
install. Clone the repository, or download `dirPathPerms.sh` from the
[latest release](https://github.com/iamteedoh/dirPathPerms/releases/latest),
then make it executable:

```bash
git clone https://github.com/iamteedoh/dirPathPerms.git
cd dirPathPerms
chmod +x dirPathPerms.sh
./dirPathPerms.sh --version
```

Put it somewhere on your `PATH` if you want it available everywhere.

## How to Run

You can either name the paths you want to check directly, or put them in an
input file (see [Input File Format](#input-file-format) below) when you have
many to audit at once.

### Interactive

```bash
./dirPathPerms.sh
```

Run with no arguments, it becomes a **session**:

1. Enter **either** a path to check (`~/Documents`) **or** a file listing paths
   to check (`myPaths.txt`) — see [how the two are told apart](#paths-vs-lists).
2. Choose whose permissions to check, and which permission to look for.
3. Read the results table, then **enter another path**. The script keeps asking,
   reusing your answers from step 2, until you press **`q`**.

### Editing keys at the prompt

The path prompt is a full readline prompt, so it behaves like your shell does:

| Key | Does |
|---|---|
| `Tab` | **Complete the path.** `~/Doc` → `~/Documents/`, `/etc/pass` → `/etc/passwd`. |
| `↑` / `↓` | Recall anything you have already typed this session — handy after a typo. |
| `Ctrl-A` / `Ctrl-E` | Jump to the start / end of the line. |
| `Ctrl-W` | Delete the previous word. |
| `Ctrl-U` | Clear the line. |
| `Ctrl-R` | Reverse-search what you typed earlier. |
| `q` | Quit the session. |

Two things to expect from completion, which differ slightly from your shell:

* When a prefix is **ambiguous** it fills in as far as the candidates agree and
  then beeps — `/var/lo` becomes `/var/log` with `/var/log` and `/var/logs` both
  present. It does not print the list of candidates.
* Completion is reliable for paths starting with `/` or `~`, which is what this
  tool wants anyway.

Nothing is written to your shell history — the session's history lives and dies
with the run.

### Non-interactive

Supply the values as flags and the script runs without prompting — ideal for
scripts, cron jobs, and CI:

```bash
# Check a single path directly
./dirPathPerms.sh --path ~/Documents --who owner --perm read

# A bare path works the same way
./dirPathPerms.sh -w owner -p r ~/Documents

# Several paths at once
./dirPathPerms.sh -P /etc/passwd -P /var/log --who group --perm write

# The full picture: every permission, for every class
./dirPathPerms.sh --path ~/Documents --all --perm all

# Does the group have write access to every listed path?
./dirPathPerms.sh --file paths.txt --who group --perm write

# Show read access for owner/group/other across all paths, colors off
./dirPathPerms.sh --all --perm read --file paths.txt --no-color

# A list file can also be passed positionally
./dirPathPerms.sh -w owner -p x paths.txt
```

Supplying everything via flags checks once and exits — no session loop — which
is what makes it usable from cron and CI.

If some (but not all) values are provided, the script prompts for the rest when
a terminal is attached, or exits with a helpful error when one is not.

<h3 id="paths-vs-lists">Paths vs. lists</h3>

A bare argument might be the path you want to check, or a file listing paths to
check. The script decides by **looking inside it**: a file whose first
meaningful line is a path (starting with `/`, `~`, or `$`) is read as a list;
anything else is checked directly. So `myPaths.txt` is a list, while
`/etc/passwd` is checked as a file — rather than having its contents mistaken
for a list of paths.

Use `--path` or `--file` when you want to say which you meant, instead of
relying on the guess.

### Command-line options

| Option | Description |
|---|---|
| `-P`, `--path PATH` | Check `PATH` directly. Repeatable. Use instead of `--file` to check one or more paths without writing a list file. |
| `-f`, `--file FILE` | Input file: one absolute path per line. Blank lines and `#` comments are ignored. |
| `-w`, `--who WHO` | Whose permission to check: `owner`\|`group`\|`other` (aliases `u`\|`g`\|`o`). |
| `-p`, `--perm PERM` | Permission to check: `read`\|`write`\|`execute`\|`all` (aliases `r`\|`w`\|`x`\|`a`). `all` checks read, write and execute together. |
| `-a`, `--all` | Check owner, group **and** other at once. |
| `--no-color` | Disable colored output (also honors the `NO_COLOR` env var). |
| `-h`, `--help` | Show help and exit. |
| `-V`, `--version` | Print the version and exit. |

## Input File Format

The input file should be a plain text file where **each line contains exactly one absolute path** to a file or directory.

* **Absolute paths are required** to ensure the script can find the files/directories regardless of where the script itself is executed from.
* **Blank lines and lines starting with `#` are ignored**, so you can annotate and space out the file freely.

### How a path line is read

Paths get written by hand and pasted out of file managers, so each line is
tidied up before it is looked up. In order:

| Written in the file | Checked as |
|---|---|
| `  /var/log  ` | `/var/log` — surrounding whitespace is trimmed |
| `/var/log` + `CRLF` | `/var/log` — a Windows line ending is stripped |
| `"/my file.txt"` or `'/my file.txt'` | `/my file.txt` — one surrounding pair of quotes is removed |
| `/my\ file.txt` | `/my file.txt` — backslash escapes are resolved (this is what dragging a file from Finder into a terminal produces) |
| `~/Documents` | `/Users/you/Documents` — a leading `~` expands to your home directory |
| `~alice/Documents` | `alice`'s home directory |
| `$HOME/Documents`, `${HOME}/Documents` | environment variables are expanded |

Two guarantees worth knowing:

* **Nothing is ever executed.** `$(...)` and backticks are left as literal text,
  so an input file can only ever name files — it is data, never a script.
* **A literal name always wins.** If a file's name genuinely contains a `~`,
  `$`, quote, or backslash, it is still checked exactly as written.

**Example Input File (`myPaths.txt`):**

```text
# system files
/etc/passwd
/home/user/important_script.sh
/var/log/app.log

# your own files — ~ and $VAR work too
~/Documents/notes.txt
$HOME/.ssh/id_ed25519

/tmp
/non/existent/path
/data/shared_folder
```

## Examples

### Scenario

Let's say you want to check if members of the owning **Group** have **Write** access to the files and directories listed in `myPaths.txt` (using the example file content above). Assume the following permissions exist:

* `/etc/passwd ` : `-rw-r--r--` (Owner: rw, Group: r, Other: r)
* `/home/user/important_script.sh` : `-rwxr-x---` (Owner: rwx, Group: rx, Other: ---)
* `/var/log/app.log` : `-rw-rw----` (Owner: rw, Group: rw, Other: ---)
* `/tmp` : `drwxrwxrwt` (Owner: rwx, Group: rwx, Other: rwt - sticky bit)
* `/non/existent/path` : Does not exist
* `/data/shared_folder` : `drwxrwx---` (Owner: rwx, Group: rwx, Other: ---)

### Running the Script (non-interactive)

```bash
./dirPathPerms.sh --file myPaths.txt --who group --perm write
```

### Expected Output

```text
Checking write permission for Group — from myPaths.txt

┌────────────────────────────────┬───────┬────────────────┐
│ Path                           │ Group │ Mode           │
├────────────────────────────────┼───────┼────────────────┤
│ /etc/passwd                    │  NO   │ -rw-r--r--     │
│ /home/user/important_script.sh │  NO   │ -rwxr-x---     │
│ /var/log/app.log               │  YES  │ -rw-rw----     │
│ /tmp                           │  YES  │ drwxrwxrwt     │
│ /non/existent/path             │   —   │ does not exist │
│ /data/shared_folder            │  YES  │ drwxrwx---     │
└────────────────────────────────┴───────┴────────────────┘

Summary: 3 granted, 2 denied, 1 skipped (5 checked).
```

`YES` is green and `NO` is red, and every other row is shaded so neighbouring
rows never blur together. Colors are omitted when output is piped or
`--no-color` is set.

With `--all`, each class gets its own column. With `--perm all`, each class
column becomes an `R  W  X` matrix of check marks:

```text
┌─────────────────────┬─────────────┬─────────────┬─────────────┬────────────┐
│                     │    Owner    │    Group    │    Other    │            │
│ Path                │  R   W   X  │  R   W   X  │  R   W   X  │ Mode       │
├─────────────────────┼─────────────┼─────────────┼─────────────┼────────────┤
│ /etc/passwd         │  ✓   ✓   ·  │  ✓   ·   ·  │  ✓   ·   ·  │ -rw-r--r-- │
│ /var/log            │  ✓   ✓   ✓  │  ✓   ·   ✓  │  ✓   ·   ✓  │ drwxr-xr-x │
└─────────────────────┴─────────────┴─────────────┴─────────────┴────────────┘

Summary: 2 path(s) checked, 0 skipped — 11 of 18 permission checks granted.
```

## Output Explanation

* **`YES`** (green): the requested permission is set for that class on that path.
* **`NO`** (red): it is not set.
* **`✓` / `·`** (with `--perm all`): the permission is, or is not, set.
* **`Mode`**: the actual mode (`-rw-r--r--`), or why there is no result —
  `does not exist` or `mode unreadable` (yellow).
* **`—`**: no result to report for that class, because the mode could not be read.
* **`Summary`**: a tally of granted / denied / skipped. When more than one class
  or permission is shown, it counts individual permission checks instead.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | The check ran. **This includes runs where permissions were denied or paths were skipped.** |
| `2` | The script could not run the check: an unknown option, a missing option value, no such input file, `--file` and `--path` combined, or nothing to check with no terminal to ask at. |

> **Reporting a denial is a successful run.** A `NO` in the table does not
> change the exit code, so `dirPathPerms.sh … || echo FAILED` will not fire on a
> denied permission — only on a usage error. Scripts that need to act on the
> result should read the output rather than the exit code:
>
> ```bash
> # alert when the group can write to anything listed
> ./dirPathPerms.sh --file paths.txt --who group --perm write --no-color \
>   | grep -q ' YES ' && echo "group-writable paths found"
> ```

## License

This project is licensed under the [GNU General Public License v3](LICENSE).

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for local
setup, the validation suite, and the pull request process.

## Security

Please report vulnerabilities privately as described in
[SECURITY.md](SECURITY.md), not through public issues.
