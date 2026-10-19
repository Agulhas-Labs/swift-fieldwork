// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The checks every agent shares, each deciding one line from what a ``DoctorProbe`` ran: the binary, one hook, the server.
public struct DoctorRun {
    public let agent: Agent
    public let probe: DoctorProbe
    /// The tools the tool's MCP server must list.
    public let expectedTools: [String]

    public init(agent: Agent, probe: DoctorProbe, expectedTools: [String]) {
        self.agent = agent
        self.probe = probe
        self.expectedTools = expectedTools
    }

    /// Whether the registered `binary` runs, then its version beside the probe's.
    public func binaryChecks(_ binary: String) -> [DoctorCheck] {
        let version = probe.version(of: binary)
        guard case let .success(registered) = version else {
            return [.fail(agent, "binary", "\(Self.reason(version)); run `\(probe.tool.name) install --agent \(agent.rawValue)` from the binary you mean to use")]
        }
        let running = probe.runningVersion
        let versionCheck = registered == running
            ? DoctorCheck.pass(agent, "version", "registered \(registered), running \(running)")
            : DoctorCheck(agent: agent, name: "version", status: .differs, detail: "registered \(registered), running \(running)")
        return [.pass(agent, "binary", "\(binary) runs"), versionCheck]
    }

    /// The registered hook `command` for `event`, fed `payload`: it must exit 0 and print nothing or, on a protocol that takes nothing else, only a JSON object.
    public func hook(_ event: String, command: String, payload: [String: Any], jsonOnly: Bool) -> DoctorCheck {
        let name = "hook \(event)"
        let input = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        guard let run = probe.run(shell: command, input: input) else {
            return .fail(agent, name, "did not start, or did not finish within the limit — \(command)")
        }
        guard run.status == 0 else {
            return .fail(agent, name, "exited \(run.status) — \(command)")
        }
        let printed = String(bytes: run.output, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if printed.isEmpty {
            return .pass(agent, name, "exit 0, silent")
        }
        let isJSON = (try? JSONSerialization.jsonObject(with: Data(printed.utf8))) is [String: Any]
        guard isJSON || !jsonOnly else {
            return .fail(agent, name, "exit 0, but printed something other than a JSON object — \(command)")
        }
        return .pass(agent, name, isJSON ? "exit 0, answered in JSON" : "exit 0, answered in text")
    }

    /// The server `command` starts, which must list every expected tool.
    public func server(_ command: String) -> DoctorCheck {
        let listed = probe.listedTools(command: command)
        guard case let .success(tools) = listed else {
            return .fail(agent, "mcp server", "\(Self.reason(listed)) — \(command)")
        }
        let missing = expectedTools.filter { !tools.contains($0) }
        guard missing.isEmpty else {
            return .fail(agent, "mcp server", "started, but lists no \(missing.joined(separator: ", ")) — \(command)")
        }
        return .pass(agent, "mcp server", "started; lists \(expectedTools.joined(separator: ", "))")
    }

    private static func reason(_ result: Result<some Any, DoctorProbe.Refusal>) -> String {
        guard case let .failure(refusal) = result else { return "" }
        return refusal.reason
    }
}
