// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Whether an agent's files hold nothing of a tool's: each is absent, or readable, parseable and free of anything that could be the tool's.
struct DoctorTraces {
    /// Whether a hooks file's bytes hold no command that names `tool`; `nil` is a file that is not there, and bytes that are not a JSON object are something.
    static func hooksHoldNothing(_ data: Data?, tool: FieldworkTool) -> Bool {
        guard let data else { return true }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return !mentions(tool, in: object["hooks"] as Any)
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

    /// Whether any `command` string beneath `value` names `tool`.
    private static func mentions(_ tool: FieldworkTool, in value: Any) -> Bool {
        if let dictionary = value as? [String: Any] {
            return dictionary.contains { key, inner in
                if key == "command", let command = inner as? String {
                    return tool.isMentioned(in: command)
                }
                return mentions(tool, in: inner)
            }
        }
        if let array = value as? [Any] {
            return array.contains { mentions(tool, in: $0) }
        }
        return false
    }
}
