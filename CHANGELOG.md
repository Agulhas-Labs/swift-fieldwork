# Changelog

## Unreleased

- Added: the doctor's agent-generic core: `DoctorCheck`, `DoctorReport` (verdict, lines and the sorted-keys `--json` encoding), `DoctorProbe` (a scratch-directory runner with an injectable launcher, `--version` and MCP `tools/list` probes), `DoctorRun` and `DoctorClaude`, the Claude Code checks (hooks registered and current, server registered, binary, each hook, the server's tools, the rule), all over the consumer's `FieldworkTool`, `HookRegistration`, `ClaudeMcpServer` and expected tool names.

## 0.4.0

- Added: `HookRegistration` (the merge, removal and fingerprint of a tool's hooks in a Claude Code `settings.json`, over a `FieldworkTool` and its events, so two tools can share one file), `HookRegistration.Event`, `HookRegistrationError` and `HookOutput` (the JSON a hook prints for Claude Code).
- Added: the Claude Code setup a tool shares: `ClaudeMcpServer` (the server's name, arguments, npm package and removal, user scope alone, or user scope and unscoped, every removal run every time), `ClaudeMcpInstall` (registering it through `claude mcp`, decided from `.claude.json`, and removing it), `ClaudeMcpRunner` and `ClaudeCLI`, `ClaudeRuleInstall` (copying and removing the agent rule) and `ClaudeInstallOutcome`.

## 0.3.0

- Added: the `SimulatorAnimations` library: `AnimationsOffLibrary`, a compiled universal simulator library that switches UIKit animations off in the app it is inserted into, with `init(environmentVariable:directory:)`, `source`, `path`, `built(compile:)`, `compileArguments(output:sourceFile:)`, `minimumIOS`, `insertingLibrary(_:into:)` and the `Compile` closure type (which returns `Fieldwork`'s `Subprocess.Output`, so a custom one imports `Fieldwork` too), and `AnimationsOffLibraryError` (`invalidEnvironmentVariable`, `notBuilt`). The consumer names the environment variable and the cache directory.

## 0.2.0

- Added: the iOS 27.0 service profile, the first `ServiceProfiles` bundles: 338 services, 94 switched off, 2 kept on because the device needs them and 5 left on because no trial had them off (`Disposition.unchecked`, the candidates of the capabilities `--keep` kept on for the input app); and a test that each bundled profile file is exactly what `simulator-profile` renders from it.
- Fixed: a health check whose first boot showed only noise and whose second boot failed outright, to boot, launch or pass the test, counted as healthy; the second boot's hard failures now stand.
- Added: the README's Simulator services section, with the credit to simslim, whose idea this is and none of whose code or tables ship here.
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
