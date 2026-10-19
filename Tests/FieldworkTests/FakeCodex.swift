// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation

/// A `codex` that keeps one server named `gizmo` in memory and answers `mcp get`, `add` and `remove` as the real one did when probed, recording every call.
final class FakeCodex: CodexMcpRunner, @unchecked Sendable {
    private let lock = NSLock()
    private let present: Bool
    private let getError: String?
    private var recorded: [Call] = []
    private var registered: (command: String, arguments: [String])?

    init(present: Bool = true, server: (command: String, arguments: [String])? = nil, getError: String? = nil) {
        self.present = present
        registered = server
        self.getError = getError
    }

    /// Every run so far, in order.
    var calls: [Call] {
        lock.withLock { recorded }
    }

    /// The server held now, `nil` when none is.
    var server: (command: String, arguments: [String])? {
        lock.withLock { registered }
    }

    func run(_ arguments: [String], home: URL) throws -> Subprocess.Output? {
        guard present else { return nil }
        return lock.withLock {
            recorded.append(Call(arguments: arguments, home: home.path))
            switch Array(arguments.prefix(2)) {
            case ["mcp", "get"]:
                if let getError {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: getError)
                }
                guard let registered else {
                    return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "Error: No MCP server named 'gizmo' found.")
                }
                let shown: [String: Any] = ["name": "gizmo", "transport": ["type": "stdio", "command": registered.command, "args": registered.arguments]]
                let json = (try? JSONSerialization.data(withJSONObject: shown)).map { String(bytes: $0, encoding: .utf8) ?? "" } ?? ""
                return Subprocess.Output(succeeded: true, standardOutput: json)
            case ["mcp", "add"]:
                let command = arguments.drop { $0 != "--" }.dropFirst()
                registered = (command.first ?? "", Array(command.dropFirst()))
                return Subprocess.Output(succeeded: true, standardOutput: "Added global MCP server 'gizmo'.")
            case ["mcp", "remove"]:
                registered = nil
                return Subprocess.Output(succeeded: true, standardOutput: "Removed global MCP server 'gizmo'.")
            default:
                return Subprocess.Output(succeeded: false, standardOutput: "", standardError: "unexpected")
            }
        }
    }
}

extension FakeCodex {
    /// One run: the arguments exactly as passed and the Codex home it was pointed at.
    struct Call: Equatable {
        let arguments: [String]
        let home: String
    }
}
