// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One check a tool's `doctor` made of one agent's install: what it checked, how it came out, and what it saw.
public struct DoctorCheck: Equatable, Sendable {
    public let agent: Agent
    /// What was checked, as the line names it: `binary`, `hook PreToolUse`, `mcp server`.
    public let name: String
    public let status: Status
    /// What was seen, and for a failure what to do about it.
    public let detail: String

    public init(agent: Agent, name: String, status: Status, detail: String) {
        self.agent = agent
        self.name = name
        self.status = status
        self.detail = detail
    }

    /// The check's one line of the answer.
    public var line: String {
        "\(agent.rawValue) \(name): \(status.rawValue) — \(detail)"
    }

    /// The check as `--json` carries it.
    public var json: [String: Any] {
        ["agent": agent.rawValue, "check": name, "status": status.rawValue, "detail": detail, "line": line]
    }

    public static func pass(_ agent: Agent, _ name: String, _ detail: String) -> DoctorCheck {
        DoctorCheck(agent: agent, name: name, status: .pass, detail: detail)
    }

    public static func fail(_ agent: Agent, _ name: String, _ detail: String) -> DoctorCheck {
        DoctorCheck(agent: agent, name: name, status: .fail, detail: detail)
    }

    public static func unknown(_ agent: Agent, _ name: String, _ detail: String) -> DoctorCheck {
        DoctorCheck(agent: agent, name: name, status: .unknown, detail: detail)
    }
}

public extension DoctorCheck {
    /// How a check came out: only `fail` makes a doctor run fail.
    enum Status: String, Sendable {
        case pass
        case fail
        /// What the check needed could not be read; never a failure.
        case unknown
        /// Two things that could match do not, which is said and never a failure: the registered binary's version and this one's.
        case differs
    }
}
