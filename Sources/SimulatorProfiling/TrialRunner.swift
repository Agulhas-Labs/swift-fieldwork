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
        let before = try jobs()
        launch(into: &trial)
        runUITest(into: &trial)
        let remaining = Double(options.logWindow) - (Self.now() - snapshotTime)
        if remaining > 0 {
            Thread.sleep(forTimeInterval: remaining)
        }
        let after = try jobs()
        trial.respawned = Self.respawned(before: before, after: after)
        trial.pidChanged = Dictionary(uniqueKeysWithValues: Self.pidChanged(before: before, after: after).compactMap { label in
            after[label].map { (label, $0.status) }
        })
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

    /// The labels that were running in `before` and crashed by `after`.
    ///
    /// A changed pid with a clean exit or a kill by launchd (`-9`, `-15`) is an idle daemon relaunched, not a crash.
    static func respawned(before: [String: LaunchctlJob], after: [String: LaunchctlJob]) -> Set<String> {
        Set(pidChanged(before: before, after: after).filter { label in
            guard let status = after[label]?.status else { return false }
            return status > 0 || (status < 0 && status != -9 && status != -15)
        })
    }

    /// The labels that were running in `before` and have another pid, or none, in `after`, sorted.
    static func pidChanged(before: [String: LaunchctlJob], after: [String: LaunchctlJob]) -> [String] {
        before.compactMap { label, job in
            guard let pid = job.pid, let now = after[label], now.pid != pid else { return nil }
            return label
        }.sorted()
    }

    /// Every job by label.
    private func jobs() throws -> [String: LaunchctlJob] {
        let output = try device.spawn(["launchctl", "list"], deadline: 30)
        guard output.succeeded else { throw ProfileDeviceError(command: "launchctl list", detail: output.standardError) }
        return LaunchctlList.jobs(parsing: output.standardOutput)
    }

    private func simctl(_ arguments: [String], deadline: TimeInterval) -> Bool {
        (try? Subprocess.run("/usr/bin/xcrun", ["simctl"] + arguments, deadline: deadline))?.succeeded ?? false
    }

    private static func now() -> Double {
        ProcessInfo.processInfo.systemUptime
    }
}
