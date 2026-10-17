// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// What the install summary prints: the lines said once, the next step per agent, and the restart lines left to the next step.
struct InstallSummaryTests {
    private static let summary = InstallSummary(
        tool: FieldworkTool(name: "gizmo"),
        saidOnce: ["unsupported on Cursor: a thing", "experimental on Codex: another thing"],
        restarts: ["restart Cursor to load the hooks"]
    )

    @Test
    func aLinePrintedByTwoSectionsIsSaidOnceInTheSummary() {
        let said = "unsupported on Cursor: a thing"
        let reports = [
            InstallStepReport(agent: .cursor, lines: ["wrote x", said]),
            InstallStepReport(agent: .codex, lines: [said]),
        ]

        #expect(Self.summary.section(reports[0]) == ["Cursor:", "  wrote x"])
        #expect(Self.summary.section(reports[1]) == ["Codex:"])
        #expect(Self.summary.summary(reports).filter { $0 == "  " + said } == ["  " + said])
    }

    @Test
    func theNextStepNamesTheToolForCodexAndNoToolElse() {
        #expect(Self.summary.nextStep(.claude) == "start a new Claude Code session")
        #expect(Self.summary.nextStep(.cursor) == "restart Cursor")
        #expect(Self.summary.nextStep(.codex) == "restart Codex; it asks you to trust the gizmo hooks when it next opens")
    }

    @Test
    func aRestartLineIsGatheredOutOfTheSectionAndNotRepeatedInTheSummary() {
        let report = InstallStepReport(agent: .cursor, lines: ["restart Cursor to load the hooks"], written: ["hooks.json"])

        #expect(Self.summary.section(report) == ["Cursor:"])
        #expect(Self.summary.summary([report]) == ["", "Summary:", "  Cursor: installed — wrote hooks.json. Next: restart Cursor."])
    }
}
