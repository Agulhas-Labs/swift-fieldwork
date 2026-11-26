// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the control boot: a log flood or respawn stands only where a stock boot straight after does not show it too.
struct FloodControlTests {
    private func measurement(logs: [String: Int] = [:], respawned: Set<String> = []) -> TrialMeasurement {
        var trial = TrialMeasurement(bootSeconds: 20)
        trial.logCounts = logs
        trial.respawned = respawned
        return trial
    }

    @Test func `a flood the stock control shows as well is cleared`() {
        let failures = HealthCheck.controlled(
            [.logFlood("dasd")], trial: measurement(logs: ["dasd": 41203]), control: measurement(logs: ["dasd": 39877])
        )

        #expect(failures.isEmpty)
    }

    @Test func `a flood the stock control does not show stands`() {
        let failures = HealthCheck.controlled(
            [.logFlood("dasd")], trial: measurement(logs: ["dasd": 41203]), control: measurement(logs: ["dasd": 300])
        )

        #expect(failures == [.logFlood("dasd")])
    }

    @Test func `a respawn stands only where the control did not respawn the label`() {
        let both = HealthCheck.controlled([.respawn("a"), .respawn("b")], trial: measurement(respawned: ["a", "b"]), control: measurement(respawned: ["a"]))

        #expect(both == [.respawn("b")])
    }

    @Test func `a failure that is not noise always stands`() {
        #expect(HealthCheck.controlled([.uiTestRunner], trial: measurement(), control: measurement()) == [.uiTestRunner])
    }

    @Test func `the flood rule takes the base it is given`() {
        #expect(HealthCheck.isFlood(count: 2000, base: 0))
        #expect(!HealthCheck.isFlood(count: 1999, base: 0))
        #expect(!HealthCheck.isFlood(count: 5000, base: 480))
        #expect(HealthCheck.isFlood(count: 5001, base: 480))
    }

    @Test func `a control is needed only for failures that are all noise`() {
        #expect(HealthCheck.needsControl([.logFlood("a"), .respawn("b")]))
        #expect(!HealthCheck.needsControl([]))
        #expect(!HealthCheck.needsControl([.logFlood("a"), .boot]))
    }

    @Test func `a trial line gives a flood its count and the floor's`() {
        let trial = measurement(logs: ["dasd": 41203])
        let floor = measurement(logs: ["dasd": 180])

        #expect(HealthCheck.detail(.logFlood("dasd"), installing: true, trial: trial, baseline: floor) == "log-flood(dasd) 41203 vs ≤ 180")
        #expect(HealthCheck.detail(.installLaunch, installing: true, trial: trial, baseline: floor) == "install-launch")
        #expect(HealthCheck.detail(.respawn("x"), installing: true, trial: trial, baseline: floor) == "respawn(x)")
    }

    @Test func `a control that fails its own check is refused naming the boot`() throws {
        var control = measurement()
        control.uiTestPassed = false
        let options = ProfileOptions(runtime: "r", deviceType: "Gizmo Phone", output: "o")
        let refusal = try #require(HealthStage.stockRefusal(control, during: "the control boot after a 3-off trial", options: options))

        #expect(refusal.contains("in the control boot after a 3-off trial"))
        #expect(refusal.contains("stock Gizmo Phone"))
    }
}
