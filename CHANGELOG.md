# Changelog

## Unreleased

## 0.1.0

- Added: the package skeleton: repository hygiene tests, lint configuration and git hooks.
- Added: the agent-layer value types (`PathKind`, `CanonicalPath`, `ShellWord`, `InvokedBinary`, `SettingsFile`, `SettingsBackupFile`, `CursorConfigJSON`), `FieldworkTool` (the consumer's name, which names the settings backup), `ProcessStreams` and `Subprocess` (a bounded child-process runner), with their tests.
- Added: `AgentPaths` (the user home and the Claude Code, Cursor and Codex locations, with a rule file named by the caller) and, on `FieldworkTool`, `hookSubcommands`, `runs(_:subcommand:)` and `isMentioned(in:)`, which recognise a registered shell command as the tool's own.
- Added: the install-agent types: `Agent`, `AgentDetection`, `AgentSelection`, `InstallPrompt`, `InstallStepReport`, `InstallCapture`, `InstallStepStopped` (a step that stopped with an exit status) and `InstallSummary`, which name the tool from a `FieldworkTool`, with `AgentPaths.codexHome(flag:environment:)` and `FieldworkTool.installedRuleName`.
- Added: the README, `CLAUDE.md`, `AGENTS.md` and `.agents/CodingGuidelines.md`.
- Added: the privacy gate, `Scripts/verify-tree.sh`, run by the pre-push hook on each pushed commit: it scans the commit's file contents and paths, and its author, committer and message, against the names of the checkout's neighbouring directories (less the public names) and the private terms, plus the home path, the login name and UUIDs.
- Added: the device-lease store, `LeaseStore`, with `DeviceLease`, `HolderProcess`, `WalkClaim` and `LeaseStoreError`, with `LeaseStore.url(for:)` public, moved from the tool that first held it with its on-disk format unchanged and pinned by a fixture.
