// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the noise floor several stock boots make.
struct NoiseFloorTests {
    private func stock(boot: Double?, launch: Double? = nil, logs: [String: Int] = [:], respawned: Set<String> = []) -> TrialMeasurement {
        var measurement = TrialMeasurement(bootSeconds: boot)
        measurement.launchSeconds = launch
        measurement.logCounts = logs
        measurement.respawned = respawned
        return measurement
    }

    private func options(_ extra: [String]) throws -> ProfileOptions {
        try ProfileOptions.parse(["--runtime", "r", "--device-type", "d", "--out", "o.json"] + extra)
    }

    @Test func `log counts take the maximum per process across disjoint and shared processes`() {
        let floor = HealthCheck.noiseFloor([
            stock(boot: 10, logs: ["assetsd": 500, "cloudd": 100]),
            stock(boot: 12, logs: ["assetsd": 900, "healthd": 40]),
        ])

        #expect(floor.logCounts == ["assetsd": 900, "cloudd": 100, "healthd": 40])
    }

    @Test func `respawns are the union`() {
        let floor = HealthCheck.noiseFloor([stock(boot: 1, respawned: ["a"]), stock(boot: 1, respawned: ["b"])])

        #expect(floor.respawned == ["a", "b"])
    }

    @Test func `times take the maximum and ignore the missing ones`() {
        let floor = HealthCheck.noiseFloor([stock(boot: 10, launch: 4), stock(boot: 14), stock(boot: 12, launch: 6)])

        #expect(floor.bootSeconds == 14)
        #expect(floor.launchSeconds == 6)
        #expect(floor.uiTestSeconds == nil)
        #expect(floor.readBack.isEmpty)
    }

    @Test func `a flood under the floor's limit passes though it fails against the smaller baseline`() {
        let small = stock(boot: 10, logs: ["assetsd": 300])
        let floor = HealthCheck.noiseFloor([small, stock(boot: 10, logs: ["assetsd": 1500])])
        var trial = stock(boot: 10, logs: ["assetsd": 9000])
        trial.readBack = []

        #expect(HealthCheck.evaluate(trial: trial, baseline: small, disabled: []) == [.logFlood("assetsd")])
        #expect(HealthCheck.evaluate(trial: trial, baseline: floor, disabled: []).isEmpty)
    }

    @Test func `baselines default to three and must be at least one`() throws {
        #expect(try options([]).baselines == 3)
        #expect(try options(["--baselines", "5"]).baselines == 5)
        #expect(throws: ProfileUsageError.self) { try options(["--baselines", "0"]) }
        #expect(ProfileOptions.usage.contains("--baselines 3"))
    }
}
