# Contributing to dirPathPerms

Thanks for helping improve dirPathPerms. This guide covers local setup,
validation, and the pull request process.

## Ways to contribute

- **Report a bug** using the repository's bug report form.
- **Request a feature** using the feature request form.
- **Send a pull request** after opening an issue for non-trivial changes.
- **Report a vulnerability privately** by following [SECURITY.md](SECURITY.md).

## Prerequisites

- Bash (the script targets `#!/bin/bash`)
- GNU coreutils `stat` (`stat -c '%A'`) to run the script itself — standard on
  Linux; on macOS install coreutils or run inside a Linux environment
- `shellcheck`
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
gitleaks git . --config .gitleaks.toml --redact --no-banner
```

When changing script behavior, exercise the interactive flow locally against a
small sample paths file and confirm both the `YES`/`NO` output and the
missing-path handling still work.

## Project layout

- `dirPathPerms.sh` — the interactive permission checker script
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
