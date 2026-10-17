// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Where the coding agents keep their configuration: the home directory every per-user path is built on, and the directories and files of Claude Code, Cursor and Codex under it.
public struct AgentPaths {
    /// The home directory every per-user path is built on: `CFFIXED_USER_HOME`, then `HOME`, each only when it holds an absolute path, and otherwise the account's home.
    ///
    /// Foundation's own lookup of the current user's home reads the account record and ignores `HOME`, so a process run under a moved `HOME` (a probe, a review, a test) would still write into the real agent directories. `CFFIXED_USER_HOME` goes first because that API honours it too.
    public static func userHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        for key in ["CFFIXED_USER_HOME", "HOME"] {
            if let value = environment[key], value.hasPrefix("/") {
                return URL(fileURLWithPath: value, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// The home the system's own tools use whatever `HOME` says: DerivedData and crash reports land here even under a moved `HOME`.
    public static var accountHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    /// `~/.claude/settings.json`, the settings file every session on this machine loads, resolved through ``claudeDirectory(environment:)`` so a moved `HOME` or a `CLAUDE_CONFIG_DIR` moves it too.
    public static var claudeSettings: URL {
        claudeSettings(environment: ProcessInfo.processInfo.environment)
    }

    /// `settings.json` in `CLAUDE_CONFIG_DIR` when `environment` sets it, since Claude Code then reads its settings there, else `~/.claude/settings.json` under the home directory it names.
    public static func claudeSettings(environment: [String: String]) -> URL {
        claudeDirectory(environment: environment).appendingPathComponent("settings.json")
    }

    /// Claude Code's own `.claude.json`, where `claude mcp add --scope user` records a server: in `CLAUDE_CONFIG_DIR` when `environment` sets it, else in the home directory it names.
    public static func claudeConfig(environment: [String: String]) -> URL {
        let directory = claudeConfigDirectory(environment: environment) ?? userHome(environment: environment)
        return directory.appendingPathComponent(".claude.json")
    }

    /// The agent rule file `name`: `rules/<name>` in `CLAUDE_CONFIG_DIR` when `environment` sets it, since Claude Code then reads its rules there, else in `~/.claude`.
    public static func claudeRule(named name: String, environment: [String: String]) -> URL {
        claudeDirectory(environment: environment).appendingPathComponent("rules", isDirectory: true).appendingPathComponent(name)
    }

    /// Claude Code's configuration directory: `CLAUDE_CONFIG_DIR` when `environment` sets it, else `~/.claude` under the home directory it names.
    public static func claudeDirectory(environment: [String: String]) -> URL {
        claudeConfigDirectory(environment: environment)
            ?? userHome(environment: environment).appendingPathComponent(".claude", isDirectory: true)
    }

    /// `CLAUDE_CONFIG_DIR` when `environment` sets it to something, which moves Claude Code's whole configuration directory.
    private static func claudeConfigDirectory(environment: [String: String]) -> URL? {
        guard let value = environment["CLAUDE_CONFIG_DIR"], !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value, isDirectory: true)
    }

    /// `~/.cursor` under the home directory `environment` names, where Cursor keeps its user-level `mcp.json` and `hooks.json`.
    public static func cursorDirectory(environment: [String: String]) -> URL {
        userHome(environment: environment).appendingPathComponent(".cursor", isDirectory: true)
    }

    /// The name of Cursor's user-level MCP server file inside ``cursorDirectory(environment:)``.
    public static var cursorMcpFileName: String {
        "mcp.json"
    }

    /// The name of Cursor's user-level hooks file inside ``cursorDirectory(environment:)``.
    public static var cursorHooksFileName: String {
        "hooks.json"
    }

    /// The name of Codex's hooks file inside ``codexDirectory(environment:)``.
    public static var codexHooksFileName: String {
        "hooks.json"
    }

    /// The name of Codex's configuration file inside ``codexDirectory(environment:)``.
    public static var codexConfigFileName: String {
        "config.toml"
    }

    /// The Codex home a run uses: `flag` (`--codex-dir`) when given, else Codex's own rule (``codexDirectory(environment:)``).
    public static func codexHome(flag: String?, environment: [String: String]) -> CodexHome {
        if let flag {
            return CodexHome(directory: URL(fileURLWithPath: flag, isDirectory: true), source: "--codex-dir")
        }
        let fromEnvironment = environment["CODEX_HOME"].map { !$0.isEmpty } ?? false
        return CodexHome(directory: codexDirectory(environment: environment), source: fromEnvironment ? "$CODEX_HOME" : "~/.codex")
    }

    /// Codex's home as Codex itself finds it: `CODEX_HOME` when `environment` sets it, else `~/.codex` under the home directory it names.
    public static func codexDirectory(environment: [String: String]) -> URL {
        if let codexHome = environment["CODEX_HOME"], !codexHome.isEmpty {
            return URL(fileURLWithPath: codexHome, isDirectory: true)
        }
        return userHome(environment: environment).appendingPathComponent(".codex", isDirectory: true)
    }
}

public extension AgentPaths {
    /// A Codex home and where it was chosen from, as a person reads it.
    struct CodexHome: Equatable, Sendable {
        public let directory: URL
        public let source: String

        public init(directory: URL, source: String) {
            self.directory = directory
            self.source = source
        }
    }
}
