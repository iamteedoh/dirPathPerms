# Contributing to dirPathPerms

Thanks for helping improve dirPathPerms. This guide covers local setup,
validation, and the pull request process.

## Ways to contribute

- **Report a bug** using the repository's bug report form.
- **Request a feature** using the feature request form.
- **Send a pull request** after opening an issue for non-trivial changes.
- **Report a vulnerability privately** by following [SECURITY.md](SECURITY.md).

## Prerequisites

- Bash (the script targets `#!/usr/bin/env bash` and runs on the Bash 3.2 that
  ships with macOS, so avoid Bash 4+ only syntax)
- `stat` — the script auto-detects the GNU (`stat -c '%A'`) and BSD/macOS
  (`stat -f '%Sp'`) variants, so no coreutils install is needed on macOS
- `shellcheck`
- `python3` — only to run the interactive (pty) tests; they are skipped without
  it, and the rest of the suite is pure Bash
- gitleaks 8.30.1 or newer

## Set up from a clean clone

```bash
git clone https://github.com/iamteedoh/dirPathPerms.git
cd dirPathPerms
chmod +x dirPathPerms.sh
```

No build step and no dependencies to install — the repository is a single
Bash script. Never commit secrets, tokens, credentials, or private
infrastructure details.

## Run the validation suite

Run the same checks that protect `main`:

```bash
git ls-files '*.sh' | xargs shellcheck
git ls-files '*.sh' | xargs -n1 bash -n
./tests/run_tests.sh
gitleaks git . --config .gitleaks.toml --redact --no-banner
```

`tests/run_tests.sh` drives the real CLI against generated fixtures and asserts
the result for each path spelling an input file can contain. Add a case there
for any change to how a path is read or resolved.

It also invokes `tests/interactive_test.py`, which attaches the script to a
pseudo-terminal to cover the prompt and its arrow-key history. Those behaviors
only exist when a tty is attached, so they cannot be tested by piping input.

## Project layout

- `dirPathPerms.sh` — the permission checker script
- `tests/run_tests.sh` — black-box test suite for the CLI
- `tests/interactive_test.py` — pty tests for the interactive prompt
- `.github/workflows/` — source validation and source-only release automation

## Pull request process

1. Create a branch from `main`.
2. Make the smallest complete change and update documentation.
3. Run the full validation suite above.
4. Use a [Conventional Commit](https://www.conventionalcommits.org/) PR title:
   `feat:`, `fix:`, `docs:`, `refactor:`, `ci:`, `test:`, or `chore:`.
5. Complete the pull request template and link the related public issue.
6. Wait for all required checks to pass, then squash-merge.

The PR title becomes the squash commit subject and drives release-please:
`fix:` creates a patch release, `feat:` creates a minor release, and a `!` or
`BREAKING CHANGE:` footer creates a breaking release.

## License

By contributing, you agree that your contributions are licensed under the
project's [GNU General Public License v3](LICENSE).
