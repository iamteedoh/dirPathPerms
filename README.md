# dirPathsPerms

# File Permission Checker Script

## Overview

This Bash script interactively checks specific file or directory permissions (Owner, Group, or Other; Read, Write, or Execute) for a list of paths provided in an input file. It provides clear, color-coded output indicating whether the specified permission is set for each path.

## Use Case

This script is useful for:

* **System Auditing:** Quickly verifying if critical files or directories have the correct permissions set for specific users (owner, group members, others).
* **Configuration Management:** Ensuring that deployed files or directories match the intended permission policies.
* **Troubleshooting:** Diagnosing permission-related issues by checking specific access rights across multiple locations.
* **Security Checks:** Identifying potentially insecure permissions (e.g., world-writable files).

## Features

* Checks permissions for files and directories listed in a specified input file.
* Allows checking for Owner (`u`), Group (`g`), or Other (`o`) permissions.
* Allows checking for Read (`r`), Write (`w`), or Execute (`x`) permissions.
* Interactive prompts guide the user to select the input file and the desired permission check.
* Input validation for file existence and permission choices.
* Clear, color-coded output:
    * **Green (`YES`)**: The specified permission is set.
    * **Red (`NO`)**: The specified permission is **not** set.
* Displays the full permission string (e.g., `Owner: rwx, Group: r-x, Other: r--`) for context in the output.
* Gracefully handles and reports paths listed in the input file that do not exist.
* Nicely formats long prompt text using line wrapping.

## Prerequisites

* A Bash-compatible shell (standard on most Linux distributions and macOS).
* Standard Unix/Linux command-line utilities, specifically:
    * `stat` (used for retrieving file status, including permissions).
    * `read`, `echo`, `printf` (standard shell built-ins).

## Installation

1.  Save the script content to a file, for example, `dirPathPerms.sh`.
2.  Make the script executable:
    ```bash
    chmod +x dirPathPerms.sh
    ```

## How to Run

1.  Create an input file containing the list of absolute paths you want to check (see [Input File Format](#input-file-format) below).
2.  Open your terminal.
3.  Navigate to the directory where you saved `dirPathPerms.sh`.
4.  Execute the script:
    ```bash
    ./dirPathPerms.sh
    ```
5.  Follow the interactive prompts:
    * Enter the path to your input file when prompted.
    * Choose whether to check permissions for Owner (`O`), Group (`G`), or Other (`E`).
    * Choose whether to check for Read (`R`), Write (`W`), or Execute (`X`) permission.

The script will then process each path in your input file and print the results to the console.

## Input File Format

The input file should be a plain text file where **each line contains exactly one absolute path** to a file or directory.

* **Absolute paths are required** to ensure the script can find the files/directories regardless of where the script itself is executed from.
* Lines starting with `#` could be used for comments if you modify the script to ignore them, but the current version treats every line as a potential path.

**Example Input File (`myPaths.txt`):**

```text
/etc/passwd
/home/user/important_script.sh
/var/log/app.log
/tmp
/non/existent/path
/data/shared_folder
```

## Examples

### Scenario

Let's say you want to check if members of the owning **Group** have **Write** access to the files and directories listed in `myPaths.txt` (using the example file content above). Assume the following permissions exist:

* `/etc/passwd ` : `-rw-r--r--` (Owner: rw, Group: r, Other: r)
* `/home/user/important_script.sh` : `-rwxr-x---` (Owner: rwx, Group: rx, Other: ---)
* `/var/log/app.log` : `-rw-wr----` (Owner: rw, Group: rw, Other: ---)
* `/tmp` : `drwxrwxrwt` (Owner: rwx, Group: rwx, Other: rwt - sticky bit)
* `/non/existent/path` : Does not exist
* `/data/shared_folder` : `drwxrwx---` (Owner: rwx, Group: rwx, Other: ---)

### Running the Script

```bash
./dirPathPerms.sh
```

### Interaction

```text
Example file format (one absolute path per line):

/location/of/dirname1
/location/of/dirname2
/location/of/filename1
/location/of/filename2

Enter the name of the file containing the directories or files we should check.
Absolute paths are required if the script is executed from a different
location.

File path: my_paths.txt  # <-- User enters the file path

Check permissions for (O)wner, (G)roup, Oth(e)r?

Choice: G              # <-- User enters 'G' for Group

Check for (R)ead, (W)rite, or e(X)ecute permissions?

Permission: W          # <-- User enters 'W' for Write
```

### Expected Output

```text

# (Output color formatting shown conceptually with Markdown)
# **Green Text** for YES, *Red Text* for NO

**/etc/passwd                              *NO write permission for Group (Owner: rw-, Group: r--, Other: r--)*
**/home/user/important_script.sh           *NO write permission for Group (Owner: rwx, Group: r-x, Other: ---)*
**/var/log/app.log                         **YES (Owner: rw-, Group: rw-, Other: ---)**
**/tmp                                     **YES (Owner: rwx, Group: rwx, Other: rwt)**
Skipping: /non/existent/path (Not a file or directory)
**/data/shared_folder                      **YES (Owner: rwx, Group: rwx, Other: ---)**
```

## Output Explanation

* `YES` (Green Text): Indicates that the requested permission (`write` in the example) is set for the specified entity (`Group` in the example) on that file or directory.
* `NO` (Red Text): Indicates that the requested permission is not set for the specified entity. The message clarifies which permission (`write`) and entity (`Group`) were checked.
* (Owner: ..., Group: ..., Other: ...): Appears on both `YES` and `NO` lines, showing the actual permission breakdown (`rwx` format) for Owner, Group, and Other for context.
* `Skipping: ... (Not a file or directory)`: This message is printed when a path listed in the input file does not exist on the filesystem.

## License

This script is provided as-is. You can consider it under the MIT License or use it freely as needed.

This `README.md` file covers the script's purpose, usage, input/output details, and provides a clear example to help users understand how to use it effectively.
