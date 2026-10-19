// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation

/// A `codex` whose `mcp get` succeeds and prints exactly `output`.
struct ShownOnly: CodexMcpRunner {
    let output: String

    func run(_: [String], home _: URL) throws -> Subprocess.Output? {
        Subprocess.Output(succeeded: true, standardOutput: output)
    }
}
