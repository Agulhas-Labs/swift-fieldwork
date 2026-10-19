// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The shape of a doctor answer, and the JSON a tool's `doctor --json` prints.
struct DoctorReportTests {
    private static let tool = FieldworkTool(name: "gizmo")

    /// The bytes a tool printed before this type existed: sorted keys, compact, no escaped em dash, slashes escaped.
    @Test
    func theEncodedBytesAreTheShapeTheToolAlreadyPrints() throws {
        let report = DoctorReport(
            tool: Self.tool,
            checks: [
                .pass(.claude, "binary", "/bin/gizmo runs"),
                .fail(.claude, "hook Stop", "exited 3 — /bin/gizmo stop"),
            ],
            skipped: [(agent: .codex, lookedFor: ["~/.codex"])],
            notInstalled: [.cursor]
        )

        let expected = """
        {"checks":[{"agent":"claude","check":"binary","detail":"\\/bin\\/gizmo runs","line":"claude binary: pass — \\/bin\\/gizmo runs","status":"pass"},\
        {"agent":"claude","check":"hook Stop","detail":"exited 3 — \\/bin\\/gizmo stop","line":"claude hook Stop: fail — exited 3 — \\/bin\\/gizmo stop","status":"fail"}],\
        "notInstalled":["cursor"],"skipped":[{"agent":"codex","lookedFor":["~\\/.codex"]}],"verdict":"failed"}
        """
        let encoded = try report.encoded()
        #expect(String(bytes: encoded, encoding: .utf8) == expected)
    }

    @Test
    func aPassingReportSaysPassedAndTheLinesFollowTheVerdict() {
        let report = DoctorReport(tool: Self.tool, checks: [.pass(.claude, "binary", "ok")], skipped: [(agent: .codex, lookedFor: ["a", "b"])])

        #expect(!report.failsTheRun)
        #expect(report.lines == [
            "doctor: passed — 0 of 1 checks failed; not detected: Codex",
            "claude binary: pass — ok",
            "codex: not detected, skipped — looked for a, b",
        ])
    }

    @Test
    func onlyAFailedCheckFailsTheRun() {
        let checks: [DoctorCheck] = [.unknown(.claude, "a", ""), DoctorCheck(agent: .claude, name: "b", status: .differs, detail: "")]

        #expect(!DoctorReport(tool: Self.tool, checks: checks).failsTheRun)
        #expect(DoctorReport(tool: Self.tool, checks: checks + [.fail(.claude, "c", "")]).failsTheRun)
    }

    @Test
    func agentsFoundWithNothingInstalledFailTheRunNamingTheTool() {
        let report = DoctorReport(tool: Self.tool, checks: [], notInstalled: [.claude])

        #expect(report.failsTheRun)
        #expect(report.verdict == "doctor: failed — no agent has gizmo installed; `gizmo install` adds it")
        #expect(report.lines.last == "claude: found, gizmo not installed — gizmo install --agent claude adds it")
    }
}
