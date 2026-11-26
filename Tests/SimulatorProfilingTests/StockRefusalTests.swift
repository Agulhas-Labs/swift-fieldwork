// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the refusal of a stock device that fails its own health check: it names each check that failed and the device type, so the reader knows what to fix without reproducing the trial.
struct StockRefusalTests {
    private var options: ProfileOptions {
        var options = ProfileOptions(runtime: "com.example.runtime", deviceType: "Gizmo Phone", output: "/dev/null")
        options.bundleID = "com.example.gizmo"
        options.onlyTesting = "GizmoUITests/TabTests/testTab"
        return options
    }

    @Test func `a stock trial that passes is not refused`() {
        #expect(HealthStage.stockRefusal(TrialMeasurement(bootSeconds: 20), trial: 1, options: options) == nil)
    }

    @Test func `a failed UI test is named with the device type`() {
        var trial = TrialMeasurement(bootSeconds: 20)
        trial.uiTestPassed = false

        let refusal = HealthStage.stockRefusal(trial, trial: 2, options: options)

        #expect(refusal == "the stock device does not pass its own health check: in baseline trial 2, the UI test GizmoUITests/TabTests/testTab failed on a stock Gizmo Phone; fix the app, the test or the device first")
    }

    @Test func `a failed boot and launch are both named`() {
        var trial = TrialMeasurement(bootSeconds: nil)
        trial.launchPassed = false

        let refusal = HealthStage.stockRefusal(trial, trial: 1, options: options)

        #expect(refusal?.contains("in baseline trial 1, the boot and the launch of com.example.gizmo failed on a stock Gizmo Phone") == true)
    }

    @Test func `a failed launch with no app names the settings app that was launched`() {
        var plain = ProfileOptions(runtime: "com.example.runtime", deviceType: "Gizmo Phone", output: "/dev/null")
        plain.bundleID = nil
        var trial = TrialMeasurement(bootSeconds: 20)
        trial.launchPassed = false

        let refusal = HealthStage.stockRefusal(trial, during: "timing pair 1", options: plain)

        #expect(refusal?.contains("in timing pair 1, the launch of com.apple.Preferences failed on a stock Gizmo Phone") == true)
    }
}
