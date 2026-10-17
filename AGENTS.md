# Agent guidelines — swift-fieldwork

The index to working in this repo. Read the files it links before starting a task.

## Project shape
swift-fieldwork is a Swift package with one library, `Fieldwork`, depending on Foundation only. It is the agent-setup layer shared by sift and SimWalk. It holds the consumer's identity (`FieldworkTool`), the Claude Code, Cursor and Codex locations (`AgentPaths`), agent detection, selection and the install prompt, settings files with their backups, a bounded `Subprocess` runner and the device-lease store; registering hooks and MCP servers, installing rules, writing Cursor's configuration and a doctor are later releases.

## Commands
- `sh setup.sh` — once per checkout: installs SwiftLint and SwiftFormat and activates `githooks/`.
- `swift build -Xswiftc -warnings-as-errors` — build.
- `sh Scripts/swift-test-gate.sh -Xswiftc -warnings-as-errors` — tests, strict, with the count checked when `sift` is installed.
- `swiftlint lint --strict` and `swiftformat Sources Tests Package.swift --lint` — style.
- `sh Scripts/verify-tree.sh` — the privacy gate (`--rev <sha>` also reads that commit's metadata and message).
- `sh Scripts/test-swift-test-gate.sh` and `sh Scripts/test-verify-tree.sh` — the two gates' self-tests.

## Docs
- [.agents/CodingGuidelines.md](.agents/CodingGuidelines.md) — conventions specific to this repo.
- [CHANGELOG.md](CHANGELOG.md) — what changed, per release.
