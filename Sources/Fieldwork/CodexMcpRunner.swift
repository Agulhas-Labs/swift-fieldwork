// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Who runs `codex mcp` for the install and the doctor, so a test never runs the real `codex` against a real Codex home.
public protocol CodexMcpRunner: Sendable {
    /// Runs `codex` with `arguments`, each passed as one argument and never through a shell, against the Codex home `home`; `nil` when there is no `codex` to run.
    func run(_ arguments: [String], home: URL) throws -> Subprocess.Output?
}
