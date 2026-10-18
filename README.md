# swift-fieldwork

The agent-setup layer shared by the Fieldwork tools: [sift](https://github.com/Agulhas-Labs/sift), a Swift code index for coding agents, and [SimWalk](https://github.com/Agulhas-Labs/simwalk), deterministic UI walks of a running iOS app.

It holds what a tool needs to find and talk to the coding agents on a machine (Claude Code, Cursor and Codex) and to share a device between runs. The tool supplies its own identity as values; the package carries none.

- `FieldworkTool`: the consumer's identity (its name and hook subcommands), and the recognition of a registered shell command as its own.
- `AgentPaths`: where Claude Code, Cursor and Codex keep their configuration, resolved from the environment.
- Detection, selection and the prompt: `AgentDetection` finds the agents, `AgentSelection` decides which to install into, `InstallPrompt` asks, and `InstallStepReport` and `InstallSummary` report what each step did.
- Settings files with their backups: `SettingsFile` and `SettingsBackupFile`.
- `Subprocess`: a bounded child-process runner.
- The lease store: `LeaseStore` and `DeviceLease`, which let one run at a time claim a simulator or device.

A second library, `SimulatorServices`, boots iOS simulators with the system services a project does not need switched off, and the `simulator-profile` tool measures which those are for each simulator runtime (see [Simulator services](#simulator-services)).

Not here yet, and coming in later releases: registering hooks and MCP servers, installing the rule file, writing Cursor's configuration, and a doctor.

## Status

0.2.0; the API may change before 1.0.

## Usage

```swift
import Fieldwork

let tool = FieldworkTool(name: "gizmo", hookSubcommands: ["pre-tool-use", "stop"])
let environment = ProcessInfo.processInfo.environment

// Which agents are on this machine?
let detection = AgentDetection.detect(AgentDetection.Machine(environment: environment), tool: tool)

// Which of them to install into, given the command's flags and whether a terminal is attached.
let flags = AgentSelection.Flags(dryRun: false)
let selection = AgentSelection.decide(flags, detection: detection, isInteractive: true)

// Ask once per detected agent; the closure reads a line from the terminal.
if case let .ask(agents) = selection {
    let prompt = InstallPrompt(tool: tool) { question in
        print(question, terminator: "")
        return readLine()
    }
    let accepted = AgentSelection.afterAsking(accepted: prompt.choose(agents))
    print(accepted)
}
```

## Simulator services

`SimulatorServices` boots an iOS simulator *slim*: with the system services a project does not need switched off. A stock iOS 27.0 simulator starts 163 of its runtime's 338 services at boot, and a UI test suite touches few of them; the iOS 27.0 profile switches off 94.

- `ServiceProfiles.profile(forRuntime:)`: the measured profile for a simulator runtime, or nil, in which case boot stock. Profiles ship as Swift source, so a tool that links the library carries them in its binary. iOS 27.0 is the first.
- `ProjectDeclarations`: what a project declares (entitlement keys, Info.plist keys, background modes, a StoreKit configuration), the `Capability` values those call for, and `unmapped`, the declarations no rule accounts for. While `unmapped` is not empty, boot stock: what those keys need is unknown.
- `ServiceProfile.plan(keeping:)`: the labels to switch off, less the services of the capabilities kept. The margin is the declaration, not the use: a project that declares HealthKit keeps every HealthKit service on, whether or not a test reaches one.
- `DisabledServicesOverride`: writes the per-device file the simulator's launchd reads at boot (merged with what is there, written atomically), reads the disabled list back from the booted device, and removes the device's directory once the device is deleted, which `simctl delete` does not.

```swift
import SimulatorServices

let runtime = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
let declarations = try ProjectDeclarations.read(entitlements: entitlementsURL, infoPlist: infoPlistURL, storeKitConfiguration: false)
if let profile = ServiceProfiles.profile(forRuntime: runtime), declarations.unmapped.isEmpty {
    let plan = profile.plan(keeping: declarations.capabilities)
    // After `simctl create`, before `simctl boot`:
    try DisabledServicesOverride().write(plan.disabled, for: udid)
}
// After the boot, check the runtime honoured it:
let disabled = try DisabledServicesOverride.readBack(udid: udid)
// After `simctl delete`:
try DisabledServicesOverride().remove(for: udid)
```

### Making a profile

`simulator-profile` measures a runtime and writes its profile. It creates its own simulator, deletes it when done (on a signal too), and refuses to run beside another booted simulator, since that would skew the costs it measures. A full run takes 30 to 60 minutes.

```sh
swift run simulator-profile --runtime com.apple.CoreSimulator.SimRuntime.iOS-27-0 --device-type "iPhone 17" \
  --app <path/to/App.app> --bundle-id <id> --xctestrun <path/to/Tests.xctestrun> --only-testing <Target/Class/test> \
  --keep <capability,…> --out profile.json --swift Sources/SimulatorServices/Profiles/iOS27Point0.swift
```

- **Cost:** a stock boot, then each on-demand service's footprint and CPU over a window (`--window`, 300 s). A service that costs more than the threshold is a candidate for switching off. These are never candidates: services launchd keeps alive or runs at load, and the infrastructure every app needs to install, launch and be tested (`InfrastructureServices`).
- **Health:** the same device with the candidates off, checked against the worst of several stock boots (`--baselines`, 3): it boots, the runtime reports the services disabled, the app installs and launches, the UI test passes in comparable time, no process floods the log, and nothing crashes and respawns. A log flood or respawn counts only if it recurs on a second boot; any other failure stands. When the check fails, a bisection finds the candidates the device needs and keeps them on (`keptByHealth`). `--keep` keeps the input app's own capabilities on throughout, so their services take no trials and are not kept for everyone as a need the bisection found; the candidates among them are never checked off, so the profile marks them `unchecked` and leaves them on until a run with an input that does not keep them checks them.
- **Output:** the profile as JSON, and with `--swift`, the Swift source to add to the library; the tool prints the registry line to add to `ServiceProfiles.sources`. Regenerate a profile rather than edit it: a test checks each bundled file is exactly what the tool renders.

The idea of switching simulator services off came from simslim (MIT). None of its code or tables ship here: every profile is measured by this tool.

## Requirements

A Swift 6.2 toolchain and macOS 13 or later. Foundation only; no dependencies. `SimulatorServices` and `simulator-profile` also need Xcode with an iOS simulator runtime.

## Depending on it

Version 0.2.0 is tagged. In `Package.swift`:

```swift
.package(url: "https://github.com/Agulhas-Labs/swift-fieldwork.git", from: "0.2.0")
```

and in the target that uses it, either library or both:

```swift
.product(name: "Fieldwork", package: "swift-fieldwork"),
.product(name: "SimulatorServices", package: "swift-fieldwork"),
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
