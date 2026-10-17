// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// How one agent's step becomes a report: a stop, any other error, the lines the installers printed, and a failure the step returned.
struct InstallStepReportTests {
    private struct Refused: Error, CustomStringConvertible {
        let description = "refused: gizmo.json is not valid JSON"
    }

    @Test
    func aStoppedStepFailsWithItsExitStatus() {
        let report = InstallStepReport.attempt(.cursor, capture: InstallCapture()) { throw InstallStepStopped(status: 3) }

        #expect(report.agent == .cursor)
        #expect(report.failures == ["stopped with exit status 3"])
    }

    @Test
    func anyOtherErrorFailsWithItsDescription() {
        let report = InstallStepReport.attempt(.claude, capture: InstallCapture()) { throw Refused() }

        #expect(report.failures == ["refused: gizmo.json is not valid JSON"])
    }

    @Test
    func capturedLinesComeFirstAndAThrownFailureIsAppendedAfterThem() {
        let capture = InstallCapture()

        let report = InstallStepReport.attempt(.codex, capture: capture) {
            capture.keep("first\nsecond")
            throw Refused()
        }

        #expect(report.lines == ["first", "second", "refused: gizmo.json is not valid JSON"])
    }

    @Test
    func aReturnedFailureIsNotAppendedTwice() {
        let capture = InstallCapture()

        let report = InstallStepReport.attempt(.codex, capture: capture) {
            capture.keep("could not write hooks.json")
            return InstallStepReport(agent: .codex, failures: ["could not write hooks.json"])
        }

        #expect(report.lines == ["could not write hooks.json"])
        #expect(report.failures == ["could not write hooks.json"])
    }
}
