# Changelog

## 0.9.0

- Added: `DeviceLease.foundShutDown` and `LeaseStore.acquire(..., foundShutDown:)` (default `false`): whether the device was shut down when the lease was taken, so a tool's release can shut down a device its lease's walk booted and leave it as it was found. The key is written only when true, so every other lease's bytes are unchanged, and a lease written before it existed reads as `nil`: leave the device as it is.

## 0.8.0

- Added: `ClaudeRuleInstall`'s `shippedBy` (default `Homebrew or npm`) and `writtenBy` (default `install.sh`, nil for none): the routes the note on a missing rule names, so a tool that ships by other routes, or has no script that writes its rule, is not told of ones it lacks.

## 0.7.0

- Added: `Subprocess.Output.failureReason` is public: what a failed run said, its error before its output, with a `Caused by:` chain after the first line, so a tool's own `codex` or `claude` calls report a failure in the words the library's do.
- Fixed: where `claude` is not on PATH, `DoctorClaude`'s server line said ``so `<install command> --agent claude` cannot register the server``, which reads as a command to run and would fail again; it names only the install command (``so `<install command>` cannot register the server``), then the `claude mcp add` to run where claude is.

## 0.6.0

- Added: `FieldworkTool.installCommand` (default `<name> install`), the command every remedy names: the doctor's (`DoctorClaude`, `DoctorRun`, `DoctorReport`), `AgentSelection`'s texts and `ClaudeRuleInstall`'s default `installCommand`, so a tool whose install verb is another (`gizmo install-hook`) is never told to run one that does not exist.
- Added: the doctor's Cursor check, `DoctorCursor` (`init(directory:probe:install:expectedTools:)`, over the tool's `CursorInstall`): the hooks in `hooks.json`, the server in `mcp.json`, the registered binary and its version, each hook fed a payload of Cursor's shape, and the server's tool list.
- Added: the doctor's Codex check, `DoctorCodex` (`init(home:runner:probe:hooks:server:expectedTools:)`, with the tool's Codex events as a `HookRegistration`): the hooks in `hooks.json` and how many of them `config.toml` records a trust for, the server `codex mcp get` shows, the binary and its version, each hook and the server's tool list. With it, the `codex mcp` lookup it uses: `CodexMcpRunner`, `CodexCLI` and `CodexMcpServer` (`getArguments`, `addArguments(binary:)`, `removeArguments` and `find(runner:home:)`, answering a `CodexMcpServer.Found`), over the tool's `ClaudeMcpServer`.
- Added: `hasNothingInstalled` on `DoctorClaude`, `DoctorCursor` and `DoctorCodex`: whether nothing of the tool's is in that agent (each file absent, or readable, parseable and free of the tool's hooks and server), so a doctor can name an agent found without the tool rather than fail it. A file that cannot be read or parsed is not nothing.

## 0.5.0

- Added: `Family` (one tool's `install` running the other tools' installs once, after its own: `Family.install(members:caller:flags:environment:besideDirectory:launch:)` over `Family.Member`, finding each on PATH or beside the caller's binary, skipping one not found, returning a `Family.Result` per member that ran, and running nothing where `FIELDWORK_FAMILY_INSTALL` is already set). The default launch, `Family.launchInheritingTerminal`, keeps the member in the caller's process group so its prompt can read the terminal, gives it Ctrl-C while the caller ignores it, and reports a member ended by a signal as `128 +` the signal number.
- Added: the doctor's agent-generic core: `DoctorCheck`, `DoctorReport` (verdict, lines and the sorted-keys `--json` encoding), `DoctorProbe` (a scratch-directory runner with an injectable launcher, `--version` and MCP `tools/list` probes), `DoctorRun` and `DoctorClaude`, the Claude Code checks (hooks registered and current, server registered, binary, each hook, the server's tools, the rule), all over the consumer's `FieldworkTool`, `HookRegistration`, `ClaudeMcpServer` and expected tool names.
- Added: the Cursor configuration a tool shares: `CursorMcpFile` (the server in `mcp.json`, over a `ClaudeMcpServer`), `CursorHooksFile` (the hooks in `hooks.json`, over a `FieldworkTool`, an agent flag and the events as `CursorHooksFile.Hook` values), `CursorInstall` (both files merged before either is written, with `CursorInstall.Refused`), `CursorHookInstaller` (returns a `CursorHookInstallResult`: the merge's `InstallOutcome` and every line to print as `printed`, with the consumer's unsupported lines) and `CursorInstallStep`; `InstallOutcome` is the new name of `ClaudeInstallOutcome`, which stays as a typealias, and its `lines` are the registration lines for every agent; `SettingsFile.read`, `merge`, `write` and `Refused` are the settings-file steps any agent's install uses; two tools can share both files.
- Added: the Cursor hook translation: `CursorHookPayload` (telling a Cursor payload from a Claude Code one), `CursorPreToolUse`, `CursorPostToolUse` and `CursorSessionStart` (a Cursor payload read as the Claude Code payload a tool's hook judges, and its answer written back in Cursor's schema, with the tool's own MCP tool names passed in as closures and rewrite notices filed through `CursorPreToolUse.Ticket` and taken by a closure) and `CursorHookOutput` (Cursor's response JSON).
- Added: public initializers for `CursorHooksFile.Change` and `SettingsFile.Refused`, so a tool's own agent file (a Codex one, say) can answer in the same values; and `ClaudeRuleInstall`'s `installCommand` (default `<tool> install`), the command the note on a missing rule names.
- Changed: `ClaudeMcpInstall.uninstall(runner:)` is now `uninstall(config:runner:)`: it reads Claude Code's config first, so a server that is not registered answers `mcp: nothing registered` without running `claude` (the real `claude mcp remove` exits 1 for an absent name), and an unreadable config is a failure that runs nothing.

## 0.4.0

- Added: `HookRegistration` (the merge, removal and fingerprint of a tool's hooks in a Claude Code `settings.json`, over a `FieldworkTool` and its events, so two tools can share one file), `HookRegistration.Event`, `HookRegistrationError` and `HookOutput` (the JSON a hook prints for Claude Code).
- Added: the Claude Code setup a tool shares: `ClaudeMcpServer` (the server's name, arguments, npm package and removal, user scope alone, or user scope and unscoped, every removal run every time), `ClaudeMcpInstall` (registering it through `claude mcp`, decided from `.claude.json`, and removing it), `ClaudeMcpRunner` and `ClaudeCLI`, `ClaudeRuleInstall` (copying and removing the agent rule) and `ClaudeInstallOutcome`.

## 0.3.0

- Added: the `SimulatorAnimations` library: `AnimationsOffLibrary`, a compiled universal simulator library that switches UIKit animations off in the app it is inserted into, with `init(environmentVariable:directory:)`, `source`, `path`, `built(compile:)`, `compileArguments(output:sourceFile:)`, `minimumIOS`, `insertingLibrary(_:into:)` and the `Compile` closure type (which returns `Fieldwork`'s `Subprocess.Output`, so a custom one imports `Fieldwork` too), and `AnimationsOffLibraryError` (`invalidEnvironmentVariable`, `notBuilt`). The consumer names the environment variable and the cache directory.

## 0.2.0

- Added: the iOS 27.0 service profile, the first `ServiceProfiles` bundles: 338 services, 94 switched off, 2 kept on because the device needs them and 5 left on because no trial had them off (`Disposition.unchecked`, the candidates of the capabilities `--keep` kept on for the input app); and a test that each bundled profile file is exactly what `simulator-profile` renders from it.
- Fixed: a health check whose first boot showed only noise and whose second boot failed outright, to boot, launch or pass the test, counted as healthy; the second boot's hard failures now stand.
- Added: the README's Simulator services section, with the credit to simslim, whose thinning inspired it and none of whose code or tables ship here.
- Added: the `simulator-profile` tool, stages 1 to 3: it inventories a runtime, measures what each service costs on a stock boot, then checks, with the candidates off, that the device still boots, reads the override back, installs and launches an app, runs a UI test and keeps its log and respawns quiet, and keeps on any candidate the device needs, comparing each trial with the worst of several stock boots, and counting a log flood or crash only when it recurs on a second boot (`--stage`, `--from`, `--app`, `--bundle-id`, `--xctestrun`, `--only-testing`, `--log-window`, `--max-kept`, `--baselines`, `--candidates`, `--keep`, `--swift`); and `Disposition.infrastructure` with `InfrastructureServices`, the services every app needs, which are never candidates.
- Added: the `SimulatorServices` library: `SimulatorRuntime`, `RuntimeInventory` (with `LaunchJob`), `Capability`, `ProjectDeclarations`, `ServiceProfile` (with `ServiceProfiles` and `SlimPlan`) and `DisabledServicesOverride`, which read a runtime's launchd jobs, map project capabilities to them and write the per-device disabled-services file a simulator reads at boot.
- Added: `ProjectDeclarations.backgroundModes` and `unmapped`, the declarations no rule accounts for, and the HealthKit, iCloud and push aliases.

## 0.1.0

- Added: the package skeleton: repository hygiene tests, lint configuration and git hooks.
- Added: the agent-layer value types (`PathKind`, `CanonicalPath`, `ShellWord`, `InvokedBinary`, `SettingsFile`, `SettingsBackupFile`, `CursorConfigJSON`), `FieldworkTool` (the consumer's name, which names the settings backup), `ProcessStreams` and `Subprocess` (a bounded child-process runner), with their tests.
- Added: `AgentPaths` (the user home and the Claude Code, Cursor and Codex locations, with a rule file named by the caller) and, on `FieldworkTool`, `hookSubcommands`, `runs(_:subcommand:)` and `isMentioned(in:)`, which recognise a registered shell command as the tool's own.
- Added: the install-agent types: `Agent`, `AgentDetection`, `AgentSelection`, `InstallPrompt`, `InstallStepReport`, `InstallCapture`, `InstallStepStopped` (a step that stopped with an exit status) and `InstallSummary`, which name the tool from a `FieldworkTool`, with `AgentPaths.codexHome(flag:environment:)` and `FieldworkTool.installedRuleName`.
- Added: the README, `CLAUDE.md`, `AGENTS.md` and `.agents/CodingGuidelines.md`.
- Added: the privacy gate, `Scripts/verify-tree.sh`, run by the pre-push hook on each pushed commit: it scans the commit's file contents and paths, and its author, committer and message, against the names of the checkout's neighbouring directories (less the public names) and the private terms, plus the home path, the login name and UUIDs.
- Added: the device-lease store, `LeaseStore`, with `DeviceLease`, `HolderProcess`, `WalkClaim` and `LeaseStoreError`, with `LeaseStore.url(for:)` public, moved from the tool that first held it with its on-disk format unchanged and pinned by a fixture.
