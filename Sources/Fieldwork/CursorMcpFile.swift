// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The MCP server a tool registers in Cursor's `~/.cursor/mcp.json`, and the merge that adds it to or takes it out of that file.
///
/// The entry is `mcpServers.<name> = {"command": <absolute binary path>, "args": <arguments>}`, the name and arguments those of the ``ClaudeMcpServer`` the consumer passes. The path is absolute because a GUI app does not inherit the shell's PATH, and it is not shell-quoted because the command and its arguments are separate fields. A server of that name is the tool's only when its command is an executable named for the tool and its arguments are exactly the server's; any other is reported and left alone, so two tools can share one file.
public struct CursorMcpFile: Equatable, Sendable {
    /// The server this file registers: its tool, its name in `mcpServers` and its arguments.
    public let server: ClaudeMcpServer

    public init(server: ClaudeMcpServer) {
        self.server = server
    }

    /// The file's name inside the Cursor directory.
    public static var fileName: String {
        AgentPaths.cursorMcpFileName
    }

    /// Whether a server entry is this tool's registration, at any path.
    public func isOurs(_ value: Any?) -> Bool {
        guard let entry = value as? [String: Any], let command = entry["command"] as? String else { return false }
        return URL(fileURLWithPath: command).lastPathComponent == server.tool.name && entry["args"] as? [String] == server.arguments
    }

    /// Registers the server in `data` (nil or empty meaning no file yet), repointing a registration of ours at another binary and leaving a foreign server of the same name alone.
    public func apply(to data: Data?, binary: String) throws -> Change {
        var file = try CursorConfigJSON.parse(data, file: Self.fileName)
        var servers = try CursorConfigJSON.object(file["mcpServers"], key: "mcpServers", file: Self.fileName)
        let outcome: Outcome
        switch servers[server.name] {
        case nil:
            servers[server.name] = ["command": binary, "args": server.arguments]
            outcome = .registered
        case let value? where isOurs(value):
            guard var entry = value as? [String: Any], let previous = entry["command"] as? String, previous != binary else {
                return Change(data: data ?? Data(), outcome: .unchanged)
            }
            // Only the path moves: anything else in the entry, an `env` someone added, is theirs to keep.
            entry["command"] = binary
            servers[server.name] = entry
            outcome = .replaced(previous: server.registered(binary: previous))
        case let value?:
            return Change(data: data ?? Data(), outcome: .foreign(Self.describe(value)))
        }
        file["mcpServers"] = servers
        return try Change(data: CursorConfigJSON.encode(file), outcome: outcome)
    }

    /// Takes this tool's server out of `data`, dropping `mcpServers` when nothing is left in it; a foreign server of the same name stays.
    public func remove(from data: Data?) throws -> Change {
        var file = try CursorConfigJSON.parse(data, file: Self.fileName)
        var servers = try CursorConfigJSON.object(file["mcpServers"], key: "mcpServers", file: Self.fileName)
        guard let value = servers[server.name] else {
            return Change(data: data ?? Data(), outcome: .unchanged)
        }
        guard isOurs(value) else {
            return Change(data: data ?? Data(), outcome: .foreign(Self.describe(value)))
        }
        servers.removeValue(forKey: server.name)
        file["mcpServers"] = servers.isEmpty ? nil : servers
        return try Change(data: CursorConfigJSON.encode(file), outcome: .removed(Self.describe(value)))
    }

    /// A server entry spelled as a person would type it: the command, then its arguments.
    private static func describe(_ value: Any) -> String {
        guard let entry = value as? [String: Any] else { return "not a server entry" }
        let command = entry["command"] as? String ?? entry["url"] as? String ?? "no command"
        let arguments = entry["args"] as? [String] ?? []
        return ([command] + arguments).joined(separator: " ")
    }
}

public extension CursorMcpFile {
    /// What a merge found and did.
    enum Outcome: Equatable, Sendable {
        /// The server was added.
        case registered
        /// Ours was there and named another binary, now repointed; the previous registration as typed.
        case replaced(previous: String)
        /// Ours was taken out; the registration as typed.
        case removed(String)
        /// Nothing to do: ours already registered at this binary, or on removal nothing of that name.
        case unchanged
        /// A server of the same name and another shape, left alone; the registration as typed.
        case foreign(String)
    }

    /// What a merge did to the file.
    struct Change: Equatable, Sendable {
        /// The file as it should be written; the input unchanged when ``changed`` is false.
        public let data: Data
        public let outcome: Outcome

        /// Whether ``data`` differs from what was read.
        public var changed: Bool {
            switch outcome {
            case .registered, .replaced, .removed: true
            case .unchanged, .foreign: false
            }
        }
    }
}
