# Security Policy

## Reporting a vulnerability

**Do not report security vulnerabilities through public GitHub issues.**

Use GitHub's private vulnerability reporting instead:

1. Open the repository's **Security** tab.
2. Select **Report a vulnerability**.
3. Provide the details requested below.

If private reporting is unavailable, contact the maintainer through the
[iamteedoh GitHub profile](https://github.com/iamteedoh).

## What to include

- A description of the issue and its potential impact
- Reproduction steps or a minimal proof of concept
- The affected release, commit, platform, and component
- A suggested remediation, if known

Never include live bearer tokens, passwords, SSH keys, private hostnames, or
unredacted logs in a report.

## Security-sensitive areas

dirPathPerms is a read-only auditing script, so the most sensitive surfaces
are:

- Handling of the user-supplied input file and the paths read from it
  (quoting, word splitting, and paths that point at symlinks or special files)
- Terminal output built from filesystem paths, including the `printf` format
  strings and ANSI color escape sequences
- Any future change that would make the script modify permissions instead of
  only reporting them
- CI and release automation workflows

## Supported versions

Security fixes land on `main` and ship in the next tagged source release. Test
against the latest release or `main` before reporting an issue.
