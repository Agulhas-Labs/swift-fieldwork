// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The Codex step of a tool's `install`: the hooks in the Codex home and the server through `codex mcp`, through the same installer as `install-hook --agent codex`, without its exit.
public struct CodexInstallStep: Equatable, Sendable {
    /// The installer this step runs.
    public let installer: CodexHookInstaller

    public init(installer: CodexHookInstaller) {
        self.installer = installer
    }

    /// Installs `binary` into the Codex home `directory` names, else the one `environment` names; the report's `lines` are `printed` from the installer.
    public func run(binary: String, environment: [String: String], directory: String? = nil, runner: any CodexMcpRunner) throws -> InstallStepReport {
        let home = AgentPaths.codexHome(flag: directory, environment: environment)
        let result = try installer.install(home: home, binary: binary, runner: runner)
        return Self.report(result)
    }

    /// The step's report for `result`, for a tool whose own step runs the installer another way.
    public static func report(_ result: HookInstallResult) -> InstallStepReport {
        // `codex mcp add` writes config.toml itself, so a registration is a change the written files do not show.
        let registered = result.outcome.lines.contains { $0.hasPrefix("mcp: registered") || $0.hasPrefix("mcp: replaced") || $0.hasPrefix("mcp: removed") }
        return InstallStepReport(agent: .codex, lines: result.printed, written: result.outcome.written, registered: registered, failures: result.outcome.failures)
    }
}
