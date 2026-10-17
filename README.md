# swift-fieldwork

The agent-setup layer shared by the Fieldwork tools: [sift](https://github.com/Agulhas-Labs/sift), a Swift code index for coding agents, and [SimWalk](https://github.com/Agulhas-Labs/simwalk), deterministic UI walks of a running iOS app.

It will register a tool's MCP server, hooks and rule file with coding agents (Claude Code, Cursor) and report what was done. The tool supplies its own identity as values; the package carries none.

## Status

Pre-release. The module is empty until 0.1.0, and the API may change before 1.0.

## Requirements

A Swift 6.2 toolchain and macOS 13 or later. Foundation only; no dependencies.

## Depending on it

Once 0.1.0 is tagged, in `Package.swift`:

```swift
.package(url: "https://github.com/Agulhas-Labs/swift-fieldwork.git", from: "0.1.0")
```

and in the target that uses it:

```swift
.product(name: "Fieldwork", package: "swift-fieldwork")
```

## Developing

Run `sh setup.sh` once. It installs SwiftLint and SwiftFormat with Homebrew and activates the git hooks in `githooks/`. Without Homebrew, install SwiftLint and SwiftFormat yourself and run `git config core.hooksPath githooks`.

The checks, which the hooks also run:

```sh
swift build -Xswiftc -warnings-as-errors
sh Scripts/swift-test-gate.sh -Xswiftc -warnings-as-errors
swiftlint lint --strict
swiftformat Sources Tests Package.swift --lint
sh Scripts/verify-tree.sh
```

`Scripts/swift-test-gate.sh` runs the tests and checks the count against the declared tests when `sift` is installed; otherwise it says it did not check. The pre-push hook runs it, the privacy gate, and the self-tests of both (`sh Scripts/test-swift-test-gate.sh`, `sh Scripts/test-verify-tree.sh`).

### Privacy gate

`Scripts/verify-tree.sh` refuses a commit that names the machine it was written on, its owner or other private work: in its files, their paths, and (with `--rev`, as the pre-push hook runs it for every pushed commit) its author, committer and message. It learns the names to look for from the directories beside the checkout, so a new neighbouring project is covered without being written down, and reads two external lists: `~/.config/fieldwork/private-terms.txt` (or `FIELDWORK_PRIVATE_TERMS`), one extended regular expression per line, which it requires; and `~/.config/fieldwork/public-names.txt` (or `FIELDWORK_PUBLIC_NAMES`), neighbouring directory names that are not private, one per line then `#` and the reason, which is optional. A contributor without the maintainer's lists can push with `FIELDWORK_PRIVACY_GATE=skip git push`: the hook skips the privacy gate alone, says so, and still runs the tests; the maintainer's push runs it.

Everything pushed here is public. Agents working in the repository should start at [AGENTS.md](AGENTS.md). Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

Apache-2.0. See [LICENSE](LICENSE).
