// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How the tool's `install` command prints what it did: each agent's installer lines under its name, then one summary saying per agent what was written and the one thing left to do, with what is unsupported and experimental said once.
public struct InstallSummary: Sendable {
    public let tool: FieldworkTool
    /// The lines an installer prints on every run that the summary says once.
    public let saidOnce: [String]
    /// The restart lines, which give way to ``nextStep(_:)``.
    public let restarts: Set<String>

    public init(tool: FieldworkTool, saidOnce: [String], restarts: Set<String>) {
        self.tool = tool
        self.saidOnce = saidOnce
        self.restarts = restarts
    }

    /// The lines an installer prints on every run, left out of its section and said once in the summary instead; the restart lines give way to ``nextStep(_:)``.
    private var gathered: Set<String> {
        Set(saidOnce).union(restarts)
    }

    /// The section for one agent's step: its name, then every line its installers printed except the gathered ones, indented.
    public func section(_ report: InstallStepReport) -> [String] {
        let gathered = gathered
        return ["\(report.agent.harness):"] + report.lines.filter { !gathered.contains($0) }.map { "  \($0)" }
    }

    /// The summary of every step: a line per agent, then the unsupported and experimental lines the steps printed, each once.
    public func summary(_ reports: [InstallStepReport]) -> [String] {
        let gathered = gathered
        var caveats: [String] = []
        for line in reports.flatMap(\.lines) where gathered.contains(line) && !restarts.contains(line) && !caveats.contains(line) {
            caveats.append(line)
        }
        return ["", "Summary:"] + reports.map { "  " + verdict($0) } + caveats.map { "  " + $0 }
    }

    /// The one manual step after an install into `agent` that changed something.
    public func nextStep(_ agent: Agent) -> String {
        switch agent {
        case .claude:
            "start a new Claude Code session"
        case .cursor:
            "restart Cursor"
        case .codex:
            "restart Codex; it asks you to trust the \(tool.name) hooks when it next opens"
        }
    }

    private func verdict(_ report: InstallStepReport) -> String {
        let name = report.agent.harness
        if !report.failures.isEmpty {
            return "\(name): failed — \(report.failures.joined(separator: "; "))"
        }
        guard report.changed else { return "\(name): already installed, nothing to do" }
        let wrote = report.written.isEmpty ? [] : ["wrote \(report.written.joined(separator: ", "))"]
        let registered = report.registered ? ["registered the MCP server"] : []
        return "\(name): installed — \((wrote + registered).joined(separator: "; ")). Next: \(nextStep(report.agent))."
    }
}
