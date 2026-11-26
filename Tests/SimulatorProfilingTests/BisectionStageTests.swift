// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the health stage's bisection wiring: the retry, the control and the trial budget, driven by scripted measurements instead of a device.
struct BisectionStageTests {
    /// Answers each boot from `respond(set, boot number)` and records the sets booted.
    private final class Script {
        var sets: [[String]] = []
        let respond: ([String], Int) -> TrialMeasurement

        init(_ respond: @escaping ([String], Int) -> TrialMeasurement) {
            self.respond = respond
        }

        func run(_ set: [String]) -> TrialMeasurement {
            sets.append(set)
            return respond(set, sets.count)
        }
    }

    private let baseline = TrialMeasurement(bootSeconds: 10)

    /// A boot that read back `set` as disabled and logged `logs`.
    private func boot(_ set: [String], logs: [String: Int] = [:], uiTestPassed: Bool = true) -> TrialMeasurement {
        var trial = TrialMeasurement(bootSeconds: 10)
        trial.readBack = Set(set)
        trial.logCounts = logs
        trial.uiTestPassed = uiTestPassed
        return trial
    }

    private func bisect(_ candidates: [String], maxTrials: Int = 100, _ script: Script) throws -> [String] {
        var options = ProfileOptions(runtime: "com.example.runtime", deviceType: "Gizmo Phone", output: "/dev/null")
        options.maxTrials = maxTrials
        return try HealthStage.bisect(candidates, baseline: baseline, installing: false, options: options, run: script.run)
    }

    @Test func `the retry's counts are compared with the control, not the first boot's`() throws {
        let script = Script { set, number in
            switch number {
            case 1: boot(set, logs: ["dasd": 50000])
            case 2: boot(set, logs: ["dasd": 5000])
            default: boot(set, logs: ["dasd": 4800])
            }
        }

        let kept = try bisect(["a"], script)

        #expect(kept.isEmpty)
        #expect(script.sets == [["a"], ["a"], []])
    }

    @Test func `a flood the control does not show keeps the candidate`() throws {
        let script = Script { set, number in
            number < 3 ? boot(set, logs: ["dasd": 50000]) : boot(set, logs: ["dasd": 100])
        }

        let kept = try bisect(["a"], script)

        #expect(kept == ["a"])
    }

    @Test func `a control whose UI test fails refuses the run`() {
        let script = Script { set, number in
            number < 3 ? boot(set, logs: ["dasd": 50000]) : boot(set, logs: ["dasd": 100], uiTestPassed: false)
        }

        let error = #expect(throws: HealthStageError.self) { try bisect(["a"], script) }

        #expect(error?.description.contains("the control boot after a 1-off trial") == true)
    }

    @Test func `a control whose boot fails refuses the run`() {
        let script = Script { set, number in
            number < 3 ? boot(set, logs: ["dasd": 50000]) : TrialMeasurement(bootSeconds: nil)
        }

        #expect(throws: HealthStageError.self) { try bisect(["a"], script) }
    }

    @Test func `a set the bisection asks about twice is booted once`() throws {
        let script = Script { set, _ in boot(set, uiTestPassed: !set.contains("b")) }

        let kept = try bisect(["a", "b"], maxTrials: 2, script)

        #expect(kept == ["b"])
        #expect(script.sets == [["a", "b"], ["a"]])
    }

    @Test func `each boot spends one trial and the one past the limit throws with the labels kept so far`() {
        let script = Script { set, _ in boot(set, uiTestPassed: !set.contains("a")) }

        let error = #expect(throws: TrialBudgetError.self) { try bisect(["a", "b"], maxTrials: 2, script) }

        #expect(error == TrialBudgetError(limit: 2, keptSoFar: ["a"]))
        #expect(script.sets.count == 2)
    }

    @Test func `a retry and a control each spend a trial`() {
        let script = Script { set, _ in boot(set, logs: ["dasd": 50000]) }

        let error = #expect(throws: TrialBudgetError.self) { try bisect(["a"], maxTrials: 2, script) }

        #expect(error == TrialBudgetError(limit: 2, keptSoFar: []))
        #expect(script.sets == [["a"], ["a"]])
    }

    @Test func `the control line marks each failure on its own`() {
        let trial = boot(["a"], logs: ["x": 5000, "y": 9000])
        let control = boot([], logs: ["x": 4800, "y": 100])
        let failures: [HealthFailure] = [.logFlood("x"), .logFlood("y")]

        let line = HealthStage.controlDetail(failures, HealthCheck.controlled(failures, trial: trial, control: control), false, trial, control)

        #expect(line == "log-flood(x) 5000 vs 4800 stock cleared, log-flood(y) 9000 vs 100 stock stands")
    }
}
