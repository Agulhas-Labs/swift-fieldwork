// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What one boot of a device with some services off showed.
public struct TrialMeasurement: Equatable, Sendable {
    /// Seconds from the boot to the finished boot; nil where the boot failed or timed out.
    public var bootSeconds: Double?
    /// Seconds to install and launch the app; nil where it did not run.
    public var launchSeconds: Double?
    /// False where the install or the launch failed.
    public var launchPassed = true
    /// Seconds the UI test took; nil where it did not run.
    public var uiTestSeconds: Double?
    /// False where the UI test failed.
    public var uiTestPassed = true
    /// Log lines in the window by the basename of the process that wrote them.
    public var logCounts: [String: Int] = [:]
    /// Labels that crashed between the two snapshots.
    public var respawned: Set<String> = []
    /// The last exit status of every label whose pid changed between the two snapshots.
    public var pidChanged: [String: Int32] = [:]
    /// The labels the booted device reports as disabled.
    public var readBack: Set<String> = []

    public init(bootSeconds: Double?) {
        self.bootSeconds = bootSeconds
    }
}

/// One way a trial differs from the stock device.
public enum HealthFailure: Hashable, Sendable {
    case boot
    case readBack
    case installLaunch
    case uiTestRunner
    case logFlood(String)
    case respawn(String)

    /// The name of the check that failed, as a profile records it; `launch` where there was no app to install.
    public func name(installing: Bool) -> String {
        switch self {
        case .boot: "boot"
        case .readBack: "read-back"
        case .installLaunch: installing ? "install-launch" : "launch"
        case .uiTestRunner: "ui-test-runner"
        case let .logFlood(process): "log-flood(\(process))"
        case let .respawn(label): "respawn(\(label))"
        }
    }
}

/// Compares a trial with the stock device's.
public enum HealthCheck {
    /// The ways `trial` is worse than `baseline`, given the labels switched off.
    ///
    /// A boot that failed ends the comparison, as nothing else was measured.
    public static func evaluate(trial: TrialMeasurement, baseline: TrialMeasurement, disabled: Set<String>) -> [HealthFailure] {
        guard trial.bootSeconds != nil else { return [.boot] }
        var failures: [HealthFailure] = []
        if !disabled.isSubset(of: trial.readBack) {
            failures.append(.readBack)
        }
        if !trial.launchPassed || (trial.launchSeconds ?? 0) > (baseline.launchSeconds ?? 0) * 3 + 10 {
            failures.append(.installLaunch)
        }
        if !trial.uiTestPassed || (trial.uiTestSeconds ?? 0) > (baseline.uiTestSeconds ?? 0) * 1.3 + 10 {
            failures.append(.uiTestRunner)
        }
        for (process, count) in trial.logCounts.sorted(by: { $0.key < $1.key }) {
            if count >= 2000, Double(count) > 10 * Double(baseline.logCounts[process] ?? 0) + 200 {
                failures.append(.logFlood(process))
            }
        }
        for label in trial.respawned.subtracting(baseline.respawned).sorted() {
            failures.append(.respawn(label))
        }
        return failures
    }

    /// The worst of several stock boots: the most a healthy device was seen to log, take or crash.
    ///
    /// A trial is compared with this, so a variation the stock boots already showed does not count against it.
    public static func noiseFloor(_ baselines: [TrialMeasurement]) -> TrialMeasurement {
        var floor = TrialMeasurement(bootSeconds: baselines.compactMap(\.bootSeconds).max())
        floor.launchSeconds = baselines.compactMap(\.launchSeconds).max()
        floor.uiTestSeconds = baselines.compactMap(\.uiTestSeconds).max()
        floor.launchPassed = baselines.allSatisfy(\.launchPassed)
        floor.uiTestPassed = baselines.allSatisfy(\.uiTestPassed)
        for baseline in baselines {
            floor.logCounts.merge(baseline.logCounts) { max($0, $1) }
            floor.respawned.formUnion(baseline.respawned)
        }
        return floor
    }

    /// Log floods and respawns vary from one first boot to the next, so one counts only when the same failure recurs on a second boot; any other failure of the second boot stands on its own, since a boot, launch or test that fails is not noise.
    public static func confirmed(_ first: [HealthFailure], retry: () throws -> [HealthFailure]) rethrows -> [HealthFailure] {
        guard !first.isEmpty, first.allSatisfy(isNoisy) else { return first }
        let again = try retry()
        return first.filter { again.contains($0) } + again.filter { !isNoisy($0) }
    }

    private static func isNoisy(_ failure: HealthFailure) -> Bool {
        switch failure {
        case .logFlood, .respawn: true
        default: false
        }
    }

    /// The checks a run makes, by the names a profile records.
    public static func checkNames(installing: Bool, testing: Bool) -> [String] {
        ["boot", "read-back", installing ? "install-launch" : "launch"] + (testing ? ["ui-test-runner"] : []) + ["log-flood", "respawn"]
    }
}
