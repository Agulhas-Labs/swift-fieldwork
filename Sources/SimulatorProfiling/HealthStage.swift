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
        let candidates: [String]
        if let given = options.candidates {
            if let unknown = given.first(where: { !known.contains($0) }) {
                throw ProfileUsageError(message: "--candidates names \(unknown), which the profile does not list")
            }
            candidates = given
        } else {
            candidates = profile.disabledLabels
        }
        guard !candidates.isEmpty else {
            ProfileCommand.log("health: no candidates to check")
            return profile
        }
        let device = try ProfileDevice.create(deviceType: options.deviceType, runtime: options.runtime, registry: registry)
        ProfileCommand.log("created device \(device.udid) for the health stage")
        do {
            let kept = try keptCandidates(candidates, on: device, options: options)
            try device.delete()
            return updated(profile, keeping: Set(kept), options: options)
        } catch {
            try? device.delete()
            throw error
        }
    }

    private static func keptCandidates(_ candidates: [String], on device: ProfileDevice, options: ProfileOptions) throws -> [String] {
        let runner = TrialRunner(device: device, options: options)
        ProfileCommand.log("health: baseline trial")
        let baseline = try runner.run(disabled: [])
        let stock = HealthCheck.evaluate(trial: baseline, baseline: baseline, disabled: [])
        guard stock.isEmpty, baseline.launchPassed, baseline.uiTestPassed else {
            throw HealthStageError(description: "the stock device does not pass its own health check; fix the app, the test or the device first")
        }
        ProfileCommand.log("trial: stock, \(String(format: "%.1f", baseline.bootSeconds ?? 0)) s boot, launch \(baseline.launchSeconds.map { String(format: "%.1f", $0) } ?? "-") s")
        let kept = try Bisection.kept(candidates: candidates, maxKept: options.maxKept) { set in
            let start = ProcessInfo.processInfo.systemUptime
            let trial = try runner.run(disabled: set)
            let failures = HealthCheck.evaluate(trial: trial, baseline: baseline, disabled: Set(set))
            let seconds = ProcessInfo.processInfo.systemUptime - start
            let names = failures.map { $0.name(installing: runner.installs) }
            ProfileCommand.log("trial: \(set.count) off, failures [\(names.joined(separator: ", "))], \(String(format: "%.1f", seconds)) s")
            if failures.contains(.readBack) {
                throw HealthStageError(description: "the runtime ignores the override: the device did not report the switched-off services as disabled")
            }
            return !failures.isEmpty
        }
        ProfileCommand.log("health: keep on \(kept.count): \(kept.joined(separator: ", "))")
        return kept
    }

    private static func updated(_ profile: ServiceProfile, keeping kept: Set<String>, options: ProfileOptions) -> ServiceProfile {
        let services = profile.services.map { entry in
            kept.contains(entry.label)
                ? ServiceEntry(
                    label: entry.label, domain: entry.domain, start: entry.start, ranAtBoot: entry.ranAtBoot,
                    peakFootprintMB: entry.peakFootprintMB, cpuSeconds: entry.cpuSeconds, disposition: .keptByHealth
                )
                : entry
        }
        let method = profile.method
        return ServiceProfile(
            schemaVersion: profile.schemaVersion, profileVersion: profile.profileVersion, runtime: profile.runtime,
            deviceType: profile.deviceType, generated: profile.generated,
            method: ProfileMethod(
                costWindowSeconds: method.costWindowSeconds, footprintThresholdMB: method.footprintThresholdMB,
                cpuThresholdSeconds: method.cpuThresholdSeconds,
                checks: HealthCheck.checkNames(installing: options.app != nil, testing: options.xctestrun != nil)
            ),
            services: services, capabilities: profile.capabilities
        )
    }
}
