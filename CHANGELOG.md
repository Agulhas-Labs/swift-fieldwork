# Changelog

## Unreleased

- Added: the package skeleton: an empty `Fieldwork` module, repository hygiene tests, lint configuration and git hooks.
- Added: the README, `CLAUDE.md`, `AGENTS.md` and `.agents/CodingGuidelines.md`.
- Added: the privacy gate, `Scripts/verify-tree.sh`, run by the pre-push hook on each pushed commit: it scans the commit's file contents and paths, and its author, committer and message, against the names of the checkout's neighbouring directories (less the public names) and the private terms, plus the home path, the login name and UUIDs.
