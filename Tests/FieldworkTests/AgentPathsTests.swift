// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers where the agents keep their files, built on scratch environments so no real `HOME` is read.
struct AgentPathsTests {
    /// A moved `HOME` moves every per-user path with it, since the account's own record would send a probe run under a scratch home into the live files.
    @Test
    func aMovedHomeIsTheHomeEveryPerUserPathFollows() {
        let environment = ["HOME": "/scratch/depot"]

        #expect(AgentPaths.userHome(environment: environment).path == "/scratch/depot")
        #expect(AgentPaths.claudeSettings(environment: environment).path == "/scratch/depot/.claude/settings.json")
    }

    /// `CFFIXED_USER_HOME` wins over `HOME`.
    @Test
    func theFixedHomeVariableWinsOverHome() {
        let environment = ["CFFIXED_USER_HOME": "/scratch/orchard", "HOME": "/scratch/depot"]

        #expect(AgentPaths.userHome(environment: environment).path == "/scratch/orchard")
    }

    /// A `HOME` that is empty, missing or relative names no directory, so the account's home stands.
    @Test(arguments: [[:], ["HOME": ""], ["HOME": "depot"]])
    func aHomeThatNamesNoDirectoryFallsBackToTheAccount(environment: [String: String]) {
        #expect(AgentPaths.userHome(environment: environment) == FileManager.default.homeDirectoryForCurrentUser)
    }

    /// A relative `CFFIXED_USER_HOME` is skipped and `HOME` is used.
    @Test
    func aRelativeFixedHomeIsSkipped() {
        let environment = ["CFFIXED_USER_HOME": "orchard", "HOME": "/scratch/depot"]

        #expect(AgentPaths.userHome(environment: environment).path == "/scratch/depot")
    }

    /// `accountHome` is what the system's own tools use whatever `HOME` says, so a moved `HOME` handed to `userHome(environment:)` leaves it where it was.
    @Test
    func accountHomeIsTheAccountsWhateverHOMESays() {
        let moved = AgentPaths.userHome(environment: ["HOME": "/tmp/scratch-home-that-does-not-exist"])

        #expect(moved.path == "/tmp/scratch-home-that-does-not-exist")
        #expect(AgentPaths.accountHome == FileManager.default.homeDirectoryForCurrentUser)
        #expect(AgentPaths.accountHome != moved)
    }

    /// Without an override, every Claude Code path sits under `~/.claude`, except `.claude.json`, which sits in the home.
    @Test
    func claudePathsDefaultToTheHome() {
        let environment = ["HOME": "/scratch/depot"]

        #expect(AgentPaths.claudeDirectory(environment: environment).path == "/scratch/depot/.claude")
        #expect(AgentPaths.claudeConfig(environment: environment).path == "/scratch/depot/.claude.json")
        #expect(AgentPaths.claudeRule(named: "gizmo.md", environment: environment).path == "/scratch/depot/.claude/rules/gizmo.md")
    }

    /// `CLAUDE_CONFIG_DIR` moves the Claude Code directory, its settings, its `.claude.json` and its rules, while Cursor stays under the user home.
    @Test
    func theClaudeConfigDirectoryMovesClaudeButNotCursor() {
        let environment = ["HOME": "/scratch/depot", "CLAUDE_CONFIG_DIR": "/scratch/claude"]

        #expect(AgentPaths.claudeDirectory(environment: environment).path == "/scratch/claude")
        #expect(AgentPaths.claudeSettings(environment: environment).path == "/scratch/claude/settings.json")
        #expect(AgentPaths.claudeConfig(environment: environment).path == "/scratch/claude/.claude.json")
        #expect(AgentPaths.claudeRule(named: "gizmo.md", environment: environment).path == "/scratch/claude/rules/gizmo.md")
        #expect(AgentPaths.cursorDirectory(environment: environment).path == "/scratch/depot/.cursor")
    }

    /// An empty `CLAUDE_CONFIG_DIR` is ignored; a relative one is not, and is taken as written.
    @Test
    func anEmptyClaudeConfigDirectoryIsIgnoredAndARelativeOneIsNot() {
        let empty = ["HOME": "/scratch/depot", "CLAUDE_CONFIG_DIR": ""]
        let relative = ["HOME": "/scratch/depot", "CLAUDE_CONFIG_DIR": "claude"]

        #expect(AgentPaths.claudeDirectory(environment: empty).path == "/scratch/depot/.claude")
        #expect(AgentPaths.claudeConfig(environment: empty).path == "/scratch/depot/.claude.json")
        #expect(AgentPaths.claudeDirectory(environment: relative).lastPathComponent == "claude")
        #expect(!AgentPaths.claudeDirectory(environment: relative).path.hasPrefix("/scratch/depot"))
    }

    /// `CODEX_HOME` moves the Codex directory; without it, Codex sits under the user home.
    @Test
    func codexHomeMovesTheCodexDirectory() {
        #expect(AgentPaths.codexDirectory(environment: ["HOME": "/scratch/depot"]).path == "/scratch/depot/.codex")
        #expect(AgentPaths.codexDirectory(environment: ["HOME": "/scratch/depot", "CODEX_HOME": "/scratch/codex"]).path == "/scratch/codex")
    }

    /// An empty `CODEX_HOME` is ignored; a relative one is not, and is taken as written.
    @Test
    func anEmptyCodexHomeIsIgnoredAndARelativeOneIsNot() {
        let empty = ["HOME": "/scratch/depot", "CODEX_HOME": ""]
        let relative = ["HOME": "/scratch/depot", "CODEX_HOME": "codex"]

        #expect(AgentPaths.codexDirectory(environment: empty).path == "/scratch/depot/.codex")
        #expect(AgentPaths.codexDirectory(environment: relative).lastPathComponent == "codex")
        #expect(!AgentPaths.codexDirectory(environment: relative).path.hasPrefix("/scratch/depot"))
    }
}
