// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SimulatorServices

/// The health stage failed in a way no set of services explains.
public struct HealthStageError: Error, CustomStringConvertible, Equatable {
    public let description: String
}

/// Checks that a device runs with a profile's candidates switched off, and keeps on the ones it needs.
enum HealthStage {
    /// The profile with the candidates the device needs marked `keptByHealth`, and the checks that ran recorded.
    static func run(_ profile: ServiceProfile, options: ProfileOptions, registry: DeviceRegistry) throws -> ServiceProfile {
        let known = Set(profile.services.map(\.label))
        var candidates: [String]
        if let given = options.candidates {
            if let unknown = given.first(where: { !known.contains($0) }) {
                throw ProfileUsageError(message: "--candidates names \(unknown), which the profile does not list")
            }
            candidates = given
        } else {
            candidates = profile.disabledLabels
        }
        for capability in options.keep {
            ProfileCommand.log("health: kept on for the input: \(capability.rawValue) (\(profile.labels(for: capability).count) labels)")
        }
        let trialled = Self.candidates(candidates, keeping: options.keep, in: profile)
        let unchecked = Set(candidates).subtracting(trialled)
        candidates = trialled
        guard !candidates.isEmpty else {
            ProfileCommand.log("health: no candidates to check")
            return updated(profile, keeping: [], unchecked: unchecked, ranChecks: false, options: options)
        }
        let device = try ProfileDevice.create(deviceType: options.deviceType, runtime: options.runtime, registry: registry)
        ProfileCommand.log("created device \(device.udid) for the health stage")
        do {
            let kept = try keptCandidates(candidates, on: device, options: options)
            try device.delete()
            return updated(profile, keeping: Set(kept), unchecked: unchecked, ranChecks: true, options: options)
        } catch {
            try? device.delete()
            throw error
        }
    }

    private static func keptCandidates(_ candidates: [String], on device: ProfileDevice, options: ProfileOptions) throws -> [String] {
        let runner = TrialRunner(device: device, options: options)
        var stocks: [TrialMeasurement] = []
        for number in 1 ... options.baselines {
            ProfileCommand.log("health: baseline trial \(number) of \(options.baselines)")
            let stock = try runner.run(disabled: [])
            guard stock.bootSeconds != nil, stock.launchPassed, stock.uiTestPassed else {
                throw HealthStageError(description: "the stock device does not pass its own health check; fix the app, the test or the device first")
            }
            ProfileCommand.log("trial: stock, \(String(format: "%.1f", stock.bootSeconds ?? 0)) s boot, launch \(stock.launchSeconds.map { String(format: "%.1f", $0) } ?? "-") s")
            stocks.append(stock)
        }
        let baseline = HealthCheck.noiseFloor(stocks)
        ProfileCommand.log(baselineLine(stocks, baseline))
        let kept = try Bisection.kept(candidates: candidates, maxKept: options.maxKept) { set in
            let start = ProcessInfo.processInfo.systemUptime
            let trial = try runner.run(disabled: set)
            let first = HealthCheck.evaluate(trial: trial, baseline: baseline, disabled: Set(set))
            try rejectReadBack(first)
            ProfileCommand.log("trial: \(set.count) off, failures [\(describe(first, runner))], \(seconds(since: start)) s")
            logPidChanges(trial)
            let failures = try HealthCheck.confirmed(first) {
                let retryStart = ProcessInfo.processInfo.systemUptime
                let retried = try runner.run(disabled: set)
                let again = HealthCheck.evaluate(trial: retried, baseline: baseline, disabled: Set(set))
                try rejectReadBack(again)
                ProfileCommand.log("trial: \(set.count) off, retry, failures [\(describe(again, runner))], \(seconds(since: retryStart)) s")
                logPidChanges(retried)
                return again
            }
            if failures != first {
                ProfileCommand.log("trial: \(set.count) off, confirmed [\(describe(failures, runner))]")
            }
            return !failures.isEmpty
        }
        ProfileCommand.log("health: keep on \(kept.count): \(kept.joined(separator: ", "))")
        try checkTiming(disabling: candidates.filter { !kept.contains($0) }, runner: runner)
        return kept
    }

    /// The number of stock and slim pairs the timing check boots.
    static let timingPairs = 2

    /// Boots the device stock and slim in turn, `timingPairs` times, and throws when the slim boot is slower at the same step in every pair (`HealthCheck.slowerInEveryPair`).
    private static func checkTiming(disabling slim: [String], runner: TrialRunner) throws {
        guard !slim.isEmpty else { return }
        var pairs: [(stock: TrialMeasurement, slim: TrialMeasurement)] = []
        for number in 1 ... timingPairs {
            let stockTrial = try runner.run(disabled: [])
            guard stockTrial.bootSeconds != nil, stockTrial.launchPassed, stockTrial.uiTestPassed else {
                throw HealthStageError(description: "timing pair \(number): the stock device failed its own health check, so the timing cannot be compared; run again on a quieter machine")
            }
            let slimTrial = try runner.run(disabled: slim)
            guard slimTrial.bootSeconds != nil, slimTrial.launchPassed, slimTrial.uiTestPassed else {
                throw HealthStageError(description: "timing pair \(number): the device with \(slim.count) services off failed a boot, launch or UI test that its bisection trial passed; run the health stage again")
            }
            ProfileCommand.log("timing: pair \(number) of \(timingPairs), stock \(timings(stockTrial)), slim \(timings(slimTrial))")
            pairs.append((stockTrial, slimTrial))
        }
        let slower = HealthCheck.slowerInEveryPair(pairs, installing: runner.installs)
        guard slower.isEmpty else {
            throw HealthStageError(description: "with \(slim.count) services off the device is slower than stock in every pair at \(slower.joined(separator: ", ")): a service it switches off is one that step waits for, and the profile was not written. Find it by timing a UI test with halves of the set off (a --candidates run is for that diagnosis only: its profile still switches off every label it does not list), then add it to InfrastructureServices so no profile switches it off")
        }
        ProfileCommand.log("timing: \(slim.count) off is as fast as stock in \(timingPairs) pairs")
    }

    private static func timings(_ trial: TrialMeasurement) -> String {
        let format = { (seconds: Double?) in seconds.map { String(format: "%.1f", $0) } ?? "-" }
        return "launch \(format(trial.launchSeconds)) s, ui test \(format(trial.uiTestSeconds)) s"
    }

    /// The candidates left once the labels serving the kept capabilities are taken out.
    static func candidates(_ candidates: [String], keeping kept: [Capability], in profile: ServiceProfile) -> [String] {
        let spared = Set(kept.flatMap { profile.labels(for: $0) })
        return candidates.filter { !spared.contains($0) }
    }

    private static func baselineLine(_ stocks: [TrialMeasurement], _ floor: TrialMeasurement) -> String {
        let noisiest = floor.logCounts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3)
            .map { "\($0.key):\($0.value)" }.joined(separator: ", ")
        return "baseline: \(stocks.count) stock boots, boot ≤ \(String(format: "%.1f", floor.bootSeconds ?? 0)) s, launch ≤ \(String(format: "%.1f", floor.launchSeconds ?? 0)) s, noisiest: \(noisiest)"
    }

    private static func logPidChanges(_ trial: TrialMeasurement) {
        guard !trial.pidChanged.isEmpty else { return }
        ProfileCommand.log("  pid changed: " + trial.pidChanged.sorted { $0.key < $1.key }.map { "\($0.key) (status \($0.value))" }.joined(separator: ", "))
    }

    private static func rejectReadBack(_ failures: [HealthFailure]) throws {
        if failures.contains(.readBack) {
            throw HealthStageError(description: "the runtime ignores the override: the device did not report the switched-off services as disabled")
        }
    }

    private static func describe(_ failures: [HealthFailure], _ runner: TrialRunner) -> String {
        failures.map { $0.name(installing: runner.installs) }.joined(separator: ", ")
    }

    private static func seconds(since start: TimeInterval) -> String {
        String(format: "%.1f", ProcessInfo.processInfo.systemUptime - start)
    }

    /// The profile with the candidates the health check kept on marked `keptByHealth`, the ones to switch off that it never had off marked `unchecked`, and what it did recorded.
    static func updated(_ profile: ServiceProfile, keeping kept: Set<String>, unchecked: Set<String>, ranChecks: Bool, options: ProfileOptions) -> ServiceProfile {
        let services = profile.services.map { entry in
            let disposition: Disposition = if kept.contains(entry.label) {
                .keptByHealth
            } else if unchecked.contains(entry.label), entry.disposition == .disable {
                .unchecked
            } else {
                entry.disposition
            }
            return ServiceEntry(
                label: entry.label, domain: entry.domain, start: entry.start, ranAtBoot: entry.ranAtBoot,
                peakFootprintMB: entry.peakFootprintMB, cpuSeconds: entry.cpuSeconds, disposition: disposition
            )
        }
        let method = profile.method
        return ServiceProfile(
            schemaVersion: profile.schemaVersion, profileVersion: profile.profileVersion, runtime: profile.runtime,
            deviceType: profile.deviceType, generated: profile.generated,
            method: ProfileMethod(
                costWindowSeconds: method.costWindowSeconds, footprintThresholdMB: method.footprintThresholdMB,
                cpuThresholdSeconds: method.cpuThresholdSeconds,
                checks: ranChecks ? HealthCheck.checkNames(installing: options.app != nil, testing: options.xctestrun != nil) : method.checks,
                keptForInput: Set(options.keep.map(\.rawValue)).sorted()
            ),
            services: services, capabilities: profile.capabilities
        )
    }
}
