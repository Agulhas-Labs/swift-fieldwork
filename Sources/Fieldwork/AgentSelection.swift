// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Which agents the tool's `install` command installs into, decided from its flags, what was detected and whether anyone is at a terminal to ask.
public enum AgentSelection: Equatable, Sendable {
    /// Install into these, without asking.
    case install([Pick])
    /// Ask once per agent, each one detected.
    case ask([Agent])
    /// Nothing to install, and why.
    case nothingToDo(String)
    /// No terminal to ask on and no flag saying what to install: the caller prints `needsFlagsText(detected:)` and installs nothing.
    case needsFlags
    /// No agent was found and none was named: the caller prints `nothingDetectedText(_:)`.
    case nothingDetected

    /// The decision: `--agent` over `--all` over `--yes`; `--dry-run` alone shows the detected agents, since it writes nothing; otherwise a terminal is asked and its absence refused.
    public static func decide(_ flags: Flags, detection: AgentDetection, isInteractive: Bool) -> AgentSelection {
        if !flags.agents.isEmpty {
            return .install(named(flags.agents, detection: detection))
        }
        if flags.all {
            return .install(Agent.allCases.map { Pick(agent: $0) })
        }
        let detected = detection.detected
        if detected.isEmpty {
            return .nothingDetected
        }
        if flags.yes || flags.dryRun {
            return .install(detected.map { Pick(agent: $0) })
        }
        if !isInteractive {
            return .needsFlags
        }
        return .ask(detected)
    }

    /// What asking came to: the agents accepted, or nothing to do when every one was declined.
    public static func afterAsking(accepted: [Agent]) -> AgentSelection {
        guard !accepted.isEmpty else { return .nothingToDo("every agent was declined, so nothing was installed") }
        return .install(accepted.map { Pick(agent: $0) })
    }

    /// Every agent and the signs it is found by, with the command that installs into it anyway.
    public static func nothingDetectedText(_ detection: AgentDetection, tool: FieldworkTool) -> String {
        let agents = detection.findings.map { finding in
            "  \(finding.agent.harness), found by \(finding.lookedFor.joined(separator: ", ")): \(tool.installCommand) --agent \(finding.agent.rawValue)"
        }
        return (["No agent found to install into. Name one to install into it anyway:"] + agents + ["Or all three: \(tool.installCommand) --all"])
            .joined(separator: "\n")
    }

    /// What was found and the command that installs into it, for a run with no terminal to ask on.
    public static func needsFlagsText(detected detection: AgentDetection, tool: FieldworkTool) -> String {
        let detected = detection.detected
        guard !detected.isEmpty else { return nothingDetectedText(detection, tool: tool) }
        let named = detected.map { "--agent \($0.rawValue)" }.joined(separator: " ")
        return [
            detection.text,
            "Nothing installed: there is no terminal to ask on. To install into what was found: \(tool.installCommand) --yes",
            "  or name each one: \(tool.installCommand) \(named)",
        ]
        .joined(separator: "\n")
    }

    /// The agents `--agent` named, once each and in ``Agent`` order, each one not detected carrying a note that it is installed because it was named.
    private static func named(_ agents: [Agent], detection: AgentDetection) -> [Pick] {
        Agent.allCases.filter(agents.contains).map { agent in
            let finding = detection.finding(agent)
            guard !finding.isDetected else { return Pick(agent: agent) }
            return Pick(agent: agent, note: "\(agent.harness) was not found (looked for \(finding.lookedFor.joined(separator: ", "))); installing because --agent \(agent.rawValue) named it")
        }
    }
}

public extension AgentSelection {
    /// The selection flags the tool's `install` command was given.
    struct Flags: Equatable, Sendable {
        /// Every `--agent`, as given.
        public var agents: [Agent]
        public var all: Bool
        public var yes: Bool
        public var dryRun: Bool

        public init(agents: [Agent] = [], all: Bool = false, yes: Bool = false, dryRun: Bool = false) {
            self.agents = agents
            self.all = all
            self.yes = yes
            self.dryRun = dryRun
        }
    }

    /// An agent to install into, and a note to print before its step when it was named without being found.
    struct Pick: Equatable, Sendable {
        public let agent: Agent
        public let note: String?

        public init(agent: Agent, note: String? = nil) {
            self.agent = agent
            self.note = note
        }
    }
}
