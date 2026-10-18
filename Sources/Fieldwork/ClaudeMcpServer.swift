// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The MCP server a tool registers with Claude Code: its name in `.claude.json`, the arguments its binary runs with, how it is recognised, and how it is removed.
public struct ClaudeMcpServer: Equatable, Sendable {
    /// The tool whose binary the server runs.
    public let tool: FieldworkTool
    /// The name the server is registered under.
    public let name: String
    /// What follows the binary in the registration.
    public let arguments: [String]
    /// The npm package `npx` runs for this server, or `nil` where the tool has none.
    public let npmPackage: String?
    /// Which `claude mcp remove` commands take the server out.
    public let removal: Removal

    public init(tool: FieldworkTool, name: String? = nil, arguments: [String] = ["mcp"], npmPackage: String? = nil, removal: Removal = .userScope) {
        self.tool = tool
        self.name = name ?? tool.name
        self.arguments = arguments
        self.npmPackage = npmPackage
        self.removal = removal
    }

    /// The arguments to `claude` that register `binary` as the user-scope server, exactly.
    public func addArguments(binary: String) -> [String] {
        ["mcp", "add", "--transport", "stdio", "--scope", "user", name, "--", binary] + arguments
    }

    /// The registration as a person pastes it.
    public func manual(binary: String) -> String {
        (["claude"] + addArguments(binary: binary).map(ShellWord.quoted)).joined(separator: " ")
    }

    /// The server as the config spells it once registered: the binary, then its arguments.
    public func registered(binary: String) -> String {
        ([binary] + arguments).joined(separator: " ")
    }

    /// The arguments to `claude` of each removal, in the order they are tried.
    public var removalArguments: [[String]] {
        switch removal {
        case .userScope:
            [["mcp", "remove", name, "--scope", "user"]]
        case .userScopeThenUnscoped:
            [["mcp", "remove", name, "--scope", "user"], ["mcp", "remove", name]]
        }
    }

    /// The removal as a command a person can paste: with two removals, the second runs only where the first fails.
    public var removalCommand: String {
        removalArguments.map { (["claude"] + $0).joined(separator: " ") }.joined(separator: " || ")
    }

    /// The user-scope server of this name in Claude Code's config at `config`, or `nil` where there is none.
    public func userEntry(in config: URL) -> Entry? {
        guard let data = try? Data(contentsOf: config),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return entry((object["mcpServers"] as? [String: Any])?[name])
    }

    /// A server entry, as the command it runs and whether that is a registration this tool makes.
    func entry(_ value: Any?) -> Entry? {
        guard let value = value as? [String: Any] else { return nil }
        let command = value["command"] as? String ?? ""
        let arguments = value["args"] as? [String] ?? []
        return Entry(command: ([command] + arguments).joined(separator: " "), ours: recognises(command: command, arguments: arguments))
    }

    /// Whether `command` run with `arguments` is this tool's server: its binary run with exactly the server's arguments, or `npx` running its package with them.
    ///
    /// Anything else, a path that merely contains the name, another package whose name starts with this one's, other arguments, is someone else's.
    func recognises(command: String, arguments given: [String]) -> Bool {
        let program = URL(fileURLWithPath: command).lastPathComponent
        if program == tool.name, given == arguments {
            return true
        }
        return program == "npx" && npxRunsServer(given)
    }

    private func npxRunsServer(_ given: [String]) -> Bool {
        guard let npmPackage else { return false }
        let rest = Array(given.drop { $0 == "-y" || $0 == "--yes" })
        guard rest.count == arguments.count + 1, Array(rest.dropFirst()) == arguments, let package = rest.first else { return false }
        return package == npmPackage || package.hasPrefix(npmPackage + "@")
    }
}

public extension ClaudeMcpServer {
    /// Which `claude mcp remove` commands take the server out.
    enum Removal: Equatable, Sendable {
        /// One removal, at user scope.
        case userScope
        /// A removal at user scope, then one with no scope where that fails.
        case userScopeThenUnscoped
    }

    /// One server entry: the command it runs, spelled as a person would type it, and whether it is this tool's.
    struct Entry: Equatable, Sendable {
        public let command: String
        public let ours: Bool
    }
}
