// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Whether an agent's files hold nothing of a tool's: each is absent, or readable, parseable and free of anything that could be the tool's.
struct DoctorTraces {
    /// Whether a hooks file's bytes hold no command that is `tool`'s: one it ``FieldworkTool/isMentioned(in:)`` or that runs one of `subcommands` as the registration recognises it; `nil` is a file that is not there, and bytes that are not a JSON object are something.
    static func hooksHoldNothing(_ data: Data?, tool: FieldworkTool, subcommands: [String]) -> Bool {
        guard let data else { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return !mentions(tool, subcommands: subcommands, in: object["hooks"] as Any)
    }

    /// A refusal as the path and why, without the install's "nothing written"; any other error as it describes itself.
    static func describe(_ error: any Error) -> String {
        if let refused = error as? SettingsFile.Refused {
            return "\(refused.path) \(refused.reason)"
        }
        return String(describing: error)
    }

    /// Whether the MCP file at `url` registers no server under `mcp`'s name and none that is the tool's; a file that cannot be read or parsed is something.
    static func serversHoldNothing(in url: URL, mcp: CursorMcpFile) -> Bool {
        let data: Data?
        do {
            // The refusal is never shown: a file that cannot be read is simply not nothing.
            data = try SettingsFile.read(url, agent: "", flag: "")
        } catch {
            return false
        }
        guard let data else { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        guard let servers = object["mcpServers"] else { return true }
        guard let table = servers as? [String: Any] else { return false }
        return table[mcp.server.name] == nil && !table.values.contains { mcp.isOurs($0) }
    }

    /// Whether any `command` string beneath `value` is `tool`'s.
    private static func mentions(_ tool: FieldworkTool, subcommands: [String], in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            return dictionary.contains { key, inner in
                if key == "command", let command = inner as? String {
                    return tool.isMentioned(in: command) || subcommands.contains { tool.runs(command, subcommand: $0) }
                }
                return mentions(tool, subcommands: subcommands, in: inner)
            }
        }
        if let array = value as? [Any] {
            return array.contains { mentions(tool, subcommands: subcommands, in: $0) }
        }
        return false
    }
}
