// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The Cursor step of a tool's `install`: the server and the hooks in the Cursor directory, through the same installer as `install-hook --agent cursor`.
public struct CursorInstallStep: Equatable, Sendable {
    /// The installer this step runs.
    public let installer: CursorHookInstaller

    public init(installer: CursorHookInstaller) {
        self.installer = installer
    }

    /// Installs `binary` into `directory`, or the Cursor directory under the home `environment` names; the report's `lines` are `printed` from the installer.
    public func run(binary: String, environment: [String: String], directory: String? = nil) throws -> InstallStepReport {
        let target = directory.map { URL(fileURLWithPath: $0) } ?? AgentPaths.cursorDirectory(environment: environment)
        let result = try installer.install(directory: target, binary: binary)
        return InstallStepReport(agent: .cursor, lines: result.printed, written: result.outcome.written, failures: result.outcome.failures)
    }
}
