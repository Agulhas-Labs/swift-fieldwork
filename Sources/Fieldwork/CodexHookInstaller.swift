// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The Codex half of a tool's `install-hook` and `uninstall-hook`: runs ``CodexInstall`` and returns what it did and every line the tool prints, in the order it prints them, starting with the Codex home it used.
///
/// The consumer passes what it says on every install: ``unsupported`` is what it does not carry over to Codex, one line each, and ``experimental`` a closing note on how far the support has been verified.
public struct CodexHookInstaller: Equatable, Sendable {
    /// The install this runs.
    public let codex: CodexInstall
    /// What the install output names as not carried over to Codex, one line each.
    public let unsupported: [String]
    /// Said on every install after the unsupported lines, or `nil` for nothing.
    public let experimental: String?

    public init(codex: CodexInstall, unsupported: [String] = [], experimental: String? = nil) {
        self.codex = codex
        self.unsupported = unsupported
        self.experimental = experimental
    }

    /// The one manual step after an install: Codex asks to trust hooks it has not seen the moment it opens, so nothing needs typing.
    public var restart: String {
        "restart Codex: it asks you to trust the \(codex.hooks.tool.name) hooks the first time it opens; approve them (again after a repoint; /hooks is where to review them)"
    }

    /// The one manual step after an uninstall that changed something.
    public var restartAfterRemoval: String {
        "restart Codex to unload the hooks; removing \(codex.hooks.tool.name)'s hooks moves any hook after them, so Codex asks you to trust those again when it next opens"
    }

    /// Registers the hooks and the server in `home` for `binary`, an absolute path; the result's `printed` is everything to print, in order.
    @discardableResult
    public func install(home: AgentPaths.CodexHome, binary: String, runner: any CodexMcpRunner) throws -> HookInstallResult {
        let outcome = try codex.install(home: home, binary: binary, binaryWord: ShellWord.quoted(binary), runner: runner)
        return HookInstallResult(outcome: outcome, printed: printed(installing: outcome, home: home))
    }

    /// Takes out what the install wrote in `home`; the result's `printed` is everything to print, in order.
    @discardableResult
    public func uninstall(home: AgentPaths.CodexHome, runner: any CodexMcpRunner) throws -> HookInstallResult {
        let outcome = try codex.uninstall(home: home, runner: runner)
        return HookInstallResult(outcome: outcome, printed: printed(uninstalling: outcome, home: home))
    }

    /// Every line an install prints for `outcome`: the home, the outcome's lines, each file written (indented), the notes and failures, the restart step whether or not anything changed, the unsupported lines and the experimental note.
    ///
    /// Public so a tool that composes its own outcome prints it the same way.
    public func printed(installing outcome: InstallOutcome, home: AgentPaths.CodexHome) -> [String] {
        var printed = [home.line]
        printed += outcome.lines
        printed += outcome.written.map { "      \($0)" }
        printed += outcome.notes + outcome.failures
        printed.append(restart)
        printed += unsupported
        if let experimental {
            printed.append(experimental)
        }
        return printed
    }

    /// Every line an uninstall prints for `outcome`: the home, then either that nothing was registered or the outcome's lines, written files, notes and failures, then the restart step when something changed or the server was removed.
    public func printed(uninstalling outcome: InstallOutcome, home: AgentPaths.CodexHome) -> [String] {
        var printed = [home.line]
        if outcome.lines.isEmpty, outcome.notes.isEmpty, outcome.failures.isEmpty {
            printed.append("codex: nothing registered in \(home.directory.path)")
        }
        printed += outcome.lines
        printed += outcome.written.map { "      \($0)" }
        printed += outcome.notes + outcome.failures
        if outcome.changed || outcome.lines.contains(where: { $0.hasPrefix("mcp: removed") }) {
            printed.append(restartAfterRemoval)
        }
        return printed
    }
}
