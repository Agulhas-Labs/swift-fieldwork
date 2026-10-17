// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A step that stopped with an exit status instead of returning a report: a consumer turns its own exit error into this inside the step.
public struct InstallStepStopped: Error, Equatable, Sendable {
    public let status: Int32

    public init(status: Int32) {
        self.status = status
    }
}

/// What one agent's step of the tool's `install` command did: the lines its installers printed, the files it wrote, whether it registered a server, and what failed.
public struct InstallStepReport: Equatable, Sendable {
    public let agent: Agent
    /// Every line the step's installers printed, in order.
    public var lines: [String]
    /// Each file the step rewrote, as the installers name it.
    public var written: [String]
    /// Whether the step registered or repointed an MCP server through the agent's own command, which writes a file this tool does not name.
    public var registered: Bool
    /// What the step set out to do and could not, one line each: any one makes the tool's `install` command exit 1.
    public var failures: [String]

    public init(agent: Agent, lines: [String] = [], written: [String] = [], registered: Bool = false, failures: [String] = []) {
        self.agent = agent
        self.lines = lines
        self.written = written
        self.registered = registered
        self.failures = failures
    }

    /// Whether the step changed anything.
    public var changed: Bool {
        !written.isEmpty || registered
    }

    /// Runs `step` for `agent` with its lines going to `capture`, turning anything it throws into a failure of this agent alone, so the agents after it still run.
    public static func attempt(_ agent: Agent, capture: InstallCapture, _ step: () throws -> InstallStepReport) -> InstallStepReport {
        var report: InstallStepReport
        var thrown = true
        do {
            report = try step()
            thrown = false
        } catch let stop as InstallStepStopped {
            report = InstallStepReport(agent: agent, failures: ["stopped with exit status \(stop.status)"])
        } catch {
            // A refusal describes itself with the path and what to do.
            report = InstallStepReport(agent: agent, failures: [String(describing: error)])
        }
        report.lines = capture.lines
        // A failure the step returns was printed by its installer already; one it threw was not, and is said under the agent's header here.
        report.lines += thrown ? report.failures : []
        return report
    }
}
