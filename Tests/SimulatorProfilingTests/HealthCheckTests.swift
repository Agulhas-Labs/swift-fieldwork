// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the comparison of a trial with the stock device, and the log counter.
struct HealthCheckTests {
    private var baseline: TrialMeasurement {
        var trial = TrialMeasurement(bootSeconds: 20)
        trial.launchSeconds = 2
        trial.uiTestSeconds = 100
        trial.logCounts = ["lsd": 50, "noisy": 1000]
        trial.respawned = ["old.respawner"]
        return trial
    }

    private func healthy() -> TrialMeasurement {
        var trial = baseline
        trial.readBack = ["x", "y"]
        return trial
    }

    private func failures(_ change: (inout TrialMeasurement) -> Void) -> [HealthFailure] {
        var trial = healthy()
        change(&trial)
        return HealthCheck.evaluate(trial: trial, baseline: baseline, disabled: ["x", "y"])
    }

    @Test func `a trial like the baseline passes`() {
        #expect(failures { _ in }.isEmpty)
    }

    @Test func `a boot that failed is the only failure`() {
        #expect(failures { $0.bootSeconds = nil
            $0.launchPassed = false
        } == [.boot])
    }

    @Test func `a label the device does not report disabled fails read-back`() {
        #expect(failures { $0.readBack = ["x"] } == [.readBack])
    }

    @Test func `a failed launch fails install-launch`() {
        #expect(failures { $0.launchPassed = false } == [.installLaunch])
    }

    @Test func `a launch over three times the baseline plus ten seconds fails`() {
        #expect(failures { $0.launchSeconds = 16 }.isEmpty)
        #expect(failures { $0.launchSeconds = 16.5 } == [.installLaunch])
    }

    @Test func `a failed UI test fails the runner check`() {
        #expect(failures { $0.uiTestPassed = false } == [.uiTestRunner])
    }

    @Test func `a UI test over 1.3 times the baseline plus ten seconds fails`() {
        #expect(failures { $0.uiTestSeconds = 140 }.isEmpty)
        #expect(failures { $0.uiTestSeconds = 141 } == [.uiTestRunner])
    }

    @Test func `a process logging at least 2000 lines and over ten times the baseline plus 200 is a flood`() {
        #expect(failures { $0.logCounts["lsd"] = 1999 }.isEmpty)
        #expect(failures { $0.logCounts["lsd"] = 2000 } == [.logFlood("lsd")])
        #expect(failures { $0.logCounts["noisy"] = 10200 }.isEmpty)
        #expect(failures { $0.logCounts["noisy"] = 10201 } == [.logFlood("noisy")])
        #expect(failures { $0.logCounts["new"] = 2500 } == [.logFlood("new")])
    }

    @Test func `a label that respawned and did not in the baseline fails`() {
        #expect(failures { $0.respawned = ["old.respawner"] }.isEmpty)
        #expect(failures { $0.respawned = ["old.respawner", "new.respawner"] } == [.respawn("new.respawner")])
    }

    @Test func `failures come in a fixed order`() {
        let all = failures {
            $0.readBack = []
            $0.launchPassed = false
            $0.uiTestPassed = false
            $0.logCounts["lsd"] = 5000
            $0.respawned = ["z", "a"]
        }

        #expect(all == [.readBack, .installLaunch, .uiTestRunner, .logFlood("lsd"), .respawn("a"), .respawn("z")])
    }

    @Test func `a trial that ran no launch and no UI test passes against a baseline that ran none`() {
        var stock = TrialMeasurement(bootSeconds: 10)
        stock.readBack = []
        var trial = TrialMeasurement(bootSeconds: 12)
        trial.readBack = ["x"]

        #expect(HealthCheck.evaluate(trial: trial, baseline: stock, disabled: ["x"]).isEmpty)
    }

    @Test func `check names say launch where no app is installed`() {
        #expect(HealthCheck.checkNames(installing: false, testing: false) == ["boot", "read-back", "launch", "log-flood", "respawn"])
        #expect(HealthCheck.checkNames(installing: true, testing: true) == ["boot", "read-back", "install-launch", "ui-test-runner", "log-flood", "respawn"])
        #expect(HealthFailure.installLaunch.name(installing: false) == "launch")
        #expect(HealthFailure.installLaunch.name(installing: true) == "install-launch")
    }

    @Test func `log lines are counted by process basename and junk is skipped`() {
        let text = """
        Filtering the log data using "..."
        {"processImagePath":"/usr/libexec/lsd","eventMessage":"a"}
        {"processImagePath":"/usr/libexec/lsd","eventMessage":"b"}
        {"processImagePath":"/sbin/launchd_sim"}
        {"eventMessage":"no path"}
        {not json
        """

        #expect(LogCounts.count(ndjson: text) == ["lsd": 2, "launchd_sim": 1])
    }
}
