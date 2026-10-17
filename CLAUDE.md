# Claude Code Configuration — swift-fieldwork

Start at **[AGENTS.md](AGENTS.md)**, the index to the project's guidelines. Read the files it links before starting a task.

## Always
- **Verify before concluding**: `swift build -Xswiftc -warnings-as-errors`,
  `sh Scripts/swift-test-gate.sh -Xswiftc -warnings-as-errors`, `swiftlint lint --strict`,
  `swiftformat Sources Tests Package.swift --lint` and `sh Scripts/verify-tree.sh` all pass (the privacy gate needs the
  maintainer's lists; a contributor pushes with `FIELDWORK_PRIVACY_GATE=skip`, as the README says), and every changed file conforms to [.agents/CodingGuidelines.md](.agents/CodingGuidelines.md).
  The pre-commit and pre-push hooks are the backstop; let them run and never bypass them.
- **A consumer's identity arrives as a value from the consumer.** Its name, binary, MCP server name, rule file
  and hook subcommands are never spelled in `Sources`.
- **No type is named `Fieldwork`.** It would shadow the module.
- **The manifest carries no warnings-as-errors flag and no `unsafeFlags`**: SwiftPM refuses `unsafeFlags` in
  a package resolved by version, and whether a warning fails a build is the consumer's call, not this
  manifest's. Strictness is passed on the command line (`-Xswiftc -warnings-as-errors`).
- **Every pushed commit is public.** No private issue references (only `swift-fieldwork#<n>`), no local
  paths, no names of unreleased or private projects.
- **Commit on a branch, with a clear message.** When a logical, self-contained unit of work is complete and
  verified, commit it: never broken or half-finished, and unrelated changes in separate commits.

## Project shape
A Swift package with one library, `Fieldwork`, depending on Foundation only. It will be the setup layer that
sift and SimWalk share when they register themselves with coding agents.
