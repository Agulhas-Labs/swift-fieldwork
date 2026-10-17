// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation
import SimulatorServices

/// Boots one device again and again with different services off, and measures each boot.
public struct TrialRunner: Sendable {
    private let device: ProfileDevice
    private let options: ProfileOptions
    private let override: DisabledServicesOverride

    /// Makes a runner on `device`, which every trial reuses.
    public init(device: ProfileDevice, options: ProfileOptions, override: DisabledServicesOverride = DisabledServicesOverride()) {
        self.device = device
        self.options = options
        self.override = override
    }

    /// Whether the trials install an app, and so name their launch check `install-launch`.
    public var installs: Bool {
        options.app != nil
    }

    /// Whether the trials run a UI test.
    public var tests: Bool {
        options.xctestrun != nil
    }

    /// Erases the device, switches `disabled` off for its next boot, boots it and measures what that showed.
    ///
    /// A boot that fails or times out is a measurement, not an error.
    public func run(disabled: [String]) throws -> TrialMeasurement {
        _ = try? device.shutdown()
        try device.erase()
        try override.remove(for: device.udid)
        if !disabled.isEmpty {
            try override.write(disabled, for: device.udid)
        }
        let bootStart = Self.now()
        do {
            try device.boot()
            try device.waitUntilBooted(deadline: 180)
        } catch {
            return TrialMeasurement(bootSeconds: nil)
        }
        var trial = TrialMeasurement(bootSeconds: Self.now() - bootStart)
        trial.readBack = (try? DisabledServicesOverride.readBack(udid: device.udid)) ?? []
        let snapshotTime = Self.now()
        let before = try pids()
        launch(into: &trial)
        runUITest(into: &trial)
        let remaining = Double(options.logWindow) - (Self.now() - snapshotTime)
        if remaining > 0 {
            Thread.sleep(forTimeInterval: remaining)
        }
        let after = try pids()
        trial.respawned = Set(before.filter { label, pid in after[label].map { $0 != pid } ?? false }.keys)
        let log = try device.spawn(["log", "show", "--last", "\(options.logWindow)s", "--style", "ndjson"], deadline: 120)
        trial.logCounts = LogCounts.count(ndjson: log.standardOutput)
        return trial
    }

    private func launch(into trial: inout TrialMeasurement) {
        let start = Self.now()
        var bundle = "com.apple.Preferences"
        var passed = true
        if let app = options.app, let bundleID = options.bundleID {
            bundle = bundleID
            passed = simctl(["install", device.udid, app], deadline: 120)
        }
        passed = passed && simctl(["launch", device.udid, bundle], deadline: 60)
        trial.launchSeconds = Self.now() - start
        trial.launchPassed = passed
        _ = simctl(["terminate", device.udid, bundle], deadline: 30)
    }

    private func runUITest(into trial: inout TrialMeasurement) {
        guard let xctestrun = options.xctestrun, let only = options.onlyTesting else { return }
        let start = Self.now()
        let output = try? Subprocess.run(
            "/usr/bin/xcodebuild",
            ["test-without-building", "-xctestrun", xctestrun, "-destination", "id=\(device.udid)", "-only-testing:\(only)"],
            deadline: 900
        )
        trial.uiTestSeconds = Self.now() - start
        trial.uiTestPassed = output?.succeeded ?? false
    }

    /// The pid of every running job by label.
    private func pids() throws -> [String: Int32] {
        let output = try device.spawn(["launchctl", "list"], deadline: 30)
        guard output.succeeded else { throw ProfileDeviceError(command: "launchctl list", detail: output.standardError) }
        return Dictionary(LaunchctlList.runningLabels(parsing: output.standardOutput).map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    private func simctl(_ arguments: [String], deadline: TimeInterval) -> Bool {
        (try? Subprocess.run("/usr/bin/xcrun", ["simctl"] + arguments, deadline: deadline))?.succeeded ?? false
    }

    private static func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }
}
