# dirPathPerms

[![CI](https://github.com/iamteedoh/dirPathPerms/actions/workflows/ci.yml/badge.svg)](https://github.com/iamteedoh/dirPathPerms/actions/workflows/ci.yml)
![License](https://img.shields.io/badge/license-GPL--3.0-blue)
[![GitHub Sponsors](https://img.shields.io/badge/GitHub%20Sponsors-%E2%9D%A4-ea4aaa?logo=githubsponsors)](https://github.com/sponsors/iamteedoh)
[![Patreon](https://img.shields.io/badge/Patreon-support-f96854?logo=patreon)](https://patreon.com/iamteedoh)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-ffdd00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/iamteedoh)

# File Permission Checker Script

## Overview

This Bash script checks specific file or directory permissions (Owner, Group, or Other; Read, Write, or Execute) for the paths you give it — either named directly, or listed one per line in an input file. It provides clear, color-coded output indicating whether the specified permission is set for each path.

It greets you with a big title banner and a short description, then runs either
**interactively** — prompting for the input file and the permission to check —
or **non-interactively** via command-line flags, which makes it easy to drop
into scripts and CI. When any required value is omitted and a terminal is
attached, the script prompts for it; when nothing is attached (a pipe or CI
job), it fails fast with a clear message instead of hanging.

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
* Checks permissions for files and directories listed in a specified input file.
* **Command-line history:** the interactive prompt supports arrow-key recall and
  full line editing, so a typo does not mean retyping the whole path.
* Allows checking for Owner (`u`), Group (`g`), or Other (`o`) permissions, or
  **all three at once** with `--all` (a compact permission matrix).
* Allows checking for Read (`r`), Write (`w`), or Execute (`x`) permissions.
* Interactive prompts guide the user to select the input file and the desired
  permission check, and validate every choice.
* Clear, color-coded output:
    * **Green (`YES`)**: The specified permission is set.
    * **Red (`NO`)**: The specified permission is **not** set.
* A **summary line** at the end with granted / denied / skipped counts.
* Displays the full permission string (e.g., `owner rwx | group r-x | other r--`)
  for context in the output.
* **Comment & blank-line support:** lines in the input file that are empty or
  start with `#` are skipped, including indented ones.
* **Forgiving path input:** a leading `~`, a `$VAR`, surrounding quotes,
  backslash-escaped spaces, stray indentation, and Windows (CRLF) line endings
  are all handled, so a path pasted out of Finder or a terminal just works.
  Paths are only ever expanded, never executed.
* Gracefully handles and reports paths listed in the input file that do not exist.
* **Cross-platform:** works with both GNU (`stat -c`) and BSD/macOS (`stat -f`)
  `stat`, so no GNU coreutils install is required on macOS.
* Color is disabled automatically when output is piped or redirected, and can be
  turned off explicitly with `--no-color` (or the `NO_COLOR` environment variable).
* `--help` and `--version` flags.

## Prerequisites

* A Bash-compatible shell (standard on most Linux distributions and macOS).
* Standard Unix/Linux command-line utilities, specifically:
    * `stat` for retrieving file permissions. The script auto-detects GNU
      (`stat -c '%A'`) and BSD/macOS (`stat -f '%Sp'`) variants, so it works on
      Linux and macOS out of the box — no GNU coreutils install required.
    * `read`, `printf`, `tr` (standard shell built-ins / utilities).

## Installation

1.  Save the script content to a file, for example, `dirPathPerms.sh`.
2.  Make the script executable:
    ```bash
    chmod +x dirPathPerms.sh
    ```

## How to Run

You can either name the paths you want to check directly, or put them in an
input file (see [Input File Format](#input-file-format) below) when you have
many to audit at once.

### Interactive

```bash
./dirPathPerms.sh
```

Follow the prompts:

* Enter **either** a path to check (`~/Documents`) **or** a file listing paths
  to check (`myPaths.txt`). A directory is checked directly; a regular file is
  read as a list of paths.
* Use the **up and down arrows** to recall anything you have already typed this
  session, and the usual line-editing keys to fix a typo.
* Choose whose permissions to check, and which permission to look for.

The script processes each path and prints the results to the console.

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

# Does the group have write access to every listed path?
./dirPathPerms.sh --file paths.txt --who group --perm write

# Show read access for owner/group/other across all paths, colors off
./dirPathPerms.sh --all --perm read --file paths.txt --no-color

# A list file can also be passed positionally
./dirPathPerms.sh -w owner -p x paths.txt
```

A bare argument is read as a **list of paths** when it is a regular file, and
**checked directly** when it is a directory. Use `--path` or `--file` when you
want to be explicit.

If some (but not all) values are provided, the script prompts for the rest when
a terminal is attached, or exits with a helpful error when one is not.

### Command-line options

| Option | Description |
|---|---|
| `-P`, `--path PATH` | Check `PATH` directly. Repeatable. Use instead of `--file` to check one or more paths without writing a list file. |
| `-f`, `--file FILE` | Input file: one absolute path per line. Blank lines and `#` comments are ignored. |
| `-w`, `--who WHO` | Whose permission to check: `owner`\|`group`\|`other` (aliases `u`\|`g`\|`o`). |
| `-p`, `--perm PERM` | Permission to check: `read`\|`write`\|`execute` (aliases `r`\|`w`\|`x`). |
| `-a`, `--all` | Check owner, group **and** other at once (permission matrix). |
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

  /etc/passwd                                   NO  (no write for Group)   [owner rw- | group r-- | other r--]
  /home/user/important_script.sh                NO  (no write for Group)   [owner rwx | group r-x | other ---]
  /var/log/app.log                              YES   [owner rw- | group rw- | other ---]
  /tmp                                          YES   [owner rwx | group rwx | other rwt]
  /non/existent/path                            SKIP (path does not exist)
  /data/shared_folder                           YES   [owner rwx | group rwx | other ---]

Summary: 3 granted, 2 denied, 1 skipped (5 checked).
```

`YES` lines are green, `NO` lines red, and `SKIP` lines yellow (colors are
omitted when output is piped or `--no-color` is set). With `--all`, each path
instead shows a per-class matrix, e.g. `u+ g- o-` for a permission present for
the owner but not the group or other.

## Output Explanation

* `YES` (Green): The requested permission (`write` in the example) is set for the specified entity (`Group` in the example) on that path.
* `NO` (Red): The requested permission is not set for the specified entity. The message clarifies which permission and entity were checked.
* `[owner ... | group ... | other ...]`: Appears on both `YES` and `NO` lines, showing the actual permission breakdown (`rwx` format) for context.
* `SKIP ...` (Yellow): Printed when a path listed in the input file does not exist or its mode can't be read.
* `Summary`: A final tally of granted / denied / skipped paths.

## License

This project is licensed under the [GNU General Public License v3](LICENSE).

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for local
setup, the validation suite, and the pull request process.

## Security

Please report vulnerabilities privately as described in
[SECURITY.md](SECURITY.md), not through public issues.
