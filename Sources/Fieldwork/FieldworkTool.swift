// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The tool this library is working for: the one place a consumer's identity enters.
public struct FieldworkTool: Equatable, Sendable {
    /// The tool's name: its binary, its MCP server name, and the word every message uses (`<name> install`).
    public let name: String

    public init(name: String) {
        self.name = name
    }

    /// The path extension of the backup left beside a settings file the tool rewrites: `bak-<name>`, so `settings.json.bak-<name>`.
    public var backupExtension: String {
        "bak-\(name)"
    }
}
