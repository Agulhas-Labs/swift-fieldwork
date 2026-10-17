// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An agent the tool's `install` command can install into, spelled as its `--agent` value.
public enum Agent: String, CaseIterable, Sendable {
    case claude
    case cursor
    case codex

    /// The agent's name as a person reads it.
    public var harness: String {
        switch self {
        case .claude:
            "Claude Code"
        case .cursor:
            "Cursor"
        case .codex:
            "Codex"
        }
    }
}
