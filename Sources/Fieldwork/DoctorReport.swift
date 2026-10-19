// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Everything a tool's `doctor` found: the checks of each agent it looked at, and the agents it did not find.
///
/// The report is a value: the consumer prints ``lines`` or writes ``encoded()``, and exits non-zero where ``failsTheRun``.
public struct DoctorReport {
    /// The tool whose install was checked, named in the verdict and in the remedy for an agent without it.
    public let tool: FieldworkTool
    public let checks: [DoctorCheck]
    /// Each agent not detected, with what was looked for.
    public let skipped: [(agent: Agent, lookedFor: [String])]
    /// Each agent found with nothing of the tool's in it, which is said and not counted; the run fails only when every agent found is one (``nothingInstalled``).
    public var notInstalled: [Agent]

    public init(tool: FieldworkTool, checks: [DoctorCheck], skipped: [(agent: Agent, lookedFor: [String])] = [], notInstalled: [Agent] = []) {
        self.tool = tool
        self.checks = checks
        self.skipped = skipped
        self.notInstalled = notInstalled
    }

    public var failed: [DoctorCheck] {
        checks.filter { $0.status == .fail }
    }

    /// Whether agents were found and none has the tool installed, so there is nothing for doctor to pass.
    public var nothingInstalled: Bool {
        checks.isEmpty && !notInstalled.isEmpty
    }

    /// Whether the answer is a failure: a check failed, or no agent found has the tool installed.
    public var failsTheRun: Bool {
        !failed.isEmpty || nothingInstalled
    }

    /// The verdict line, first in the answer.
    public var verdict: String {
        if nothingInstalled {
            return "doctor: failed — no agent has \(tool.name) installed; `\(tool.name) install` adds it"
        }
        let outcome = failed.isEmpty ? "passed" : "failed"
        var line = "doctor: \(outcome) — \(failed.count) of \(checks.count) checks failed"
        if !skipped.isEmpty {
            line += "; not detected: \(skipped.map(\.agent.harness).joined(separator: ", "))"
        }
        return line
    }

    /// The verdict, then one line per check, then one per agent found without the tool, then one per agent skipped.
    public var lines: [String] {
        let missing = notInstalled.map { "\($0.rawValue): found, \(tool.name) not installed — \(tool.name) install --agent \($0.rawValue) adds it" }
        let absent = skipped.map { "\($0.agent.rawValue): not detected, skipped — looked for \($0.lookedFor.joined(separator: ", "))" }
        return [verdict] + checks.map(\.line) + missing + absent
    }

    /// The same answer as one JSON object.
    public var json: [String: Any] {
        [
            "verdict": failsTheRun ? "failed" : "passed",
            "checks": checks.map(\.json),
            "notInstalled": notInstalled.map(\.rawValue),
            "skipped": skipped.map { ["agent": $0.agent.rawValue, "lookedFor": $0.lookedFor] as [String: Any] },
        ]
    }

    /// ``json`` as `--json` prints it: sorted keys, compact.
    public func encoded() throws -> Data {
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
}
