// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A tool's server in Codex's `config.toml`, read and changed only through `codex mcp`, which owns that file.
///
/// Ownership is judged as in Cursor's `mcp.json` (``CursorMcpFile/isOurs(_:)``): the tool's binary at any path, run with the server's arguments. `codex mcp add` replaces a server of the same name without a word, so what is there is always asked for first.
public struct CodexMcpServer: Equatable, Sendable {
    /// The server registered: its tool, its name and its arguments.
    public let server: ClaudeMcpServer

    public init(server: ClaudeMcpServer) {
        self.server = server
    }

    /// The arguments to `codex` that show the server, as JSON.
    public var getArguments: [String] {
        ["mcp", "get", server.name, "--json"]
    }

    /// The arguments to `codex` that register `binary` as the server.
    public func addArguments(binary: String) -> [String] {
        ["mcp", "add", server.name, "--", binary] + server.arguments
    }

    /// The arguments to `codex` that take the server out.
    public var removeArguments: [String] {
        ["mcp", "remove", server.name]
    }

    /// What `codex mcp get` says is registered under the name in `home`; a failure that is not "no such server" is refused, since reading it as absent would let `add` replace whatever is there.
    public func find(runner: any CodexMcpRunner, home: URL) throws -> Found {
        guard let output = try runner.run(getArguments, home: home) else { return .noCodex }
        guard output.succeeded else {
            if (output.standardError + output.standardOutput).contains("No MCP server named") {
                return .absent
            }
            throw refusal(home, "could not be read by `codex \(getArguments.joined(separator: " "))`: \(output.failureReason)")
        }
        guard let shown = try? JSONSerialization.jsonObject(with: Data(output.standardOutput.utf8)) as? [String: Any],
              let transport = shown["transport"] as? [String: Any]
        else {
            throw refusal(home, "could not be read: `codex \(getArguments.joined(separator: " "))` printed no server transport")
        }
        let command = transport["command"] as? String ?? transport["url"] as? String ?? "?"
        let described = ([command] + (transport["args"] as? [String] ?? [])).joined(separator: " ")
        return CursorMcpFile(server: server).isOurs(transport) ? .ours(command) : .foreign(described)
    }

    private func refusal(_ home: URL, _ reason: String) -> SettingsFile.Refused {
        SettingsFile.Refused(path: home.appendingPathComponent(AgentPaths.codexConfigFileName).path, reason: reason, agent: "codex")
    }
}

public extension CodexMcpServer {
    /// What is registered under the server's name.
    enum Found: Equatable, Sendable {
        /// There is no `codex` on PATH to ask.
        case noCodex
        /// Nothing is.
        case absent
        /// This tool's server, running the binary at this path.
        case ours(String)
        /// Something else, spelled as a person would type it.
        case foreign(String)
    }
}
