// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What a Claude Code install step did: the lines it printed, what it left alone, the files it rewrote, and what it set out to do and could not.
public struct ClaudeInstallOutcome: Equatable, Sendable {
    /// One line per registration made, repointed, found already in place or taken out.
    public var lines: [String]
    /// What was left alone and why, and any backup that could not be kept.
    public var notes: [String]
    /// Each file rewritten, as an answer names it.
    public var written: [String]
    /// What the step set out to do and could not, one line each; a command that says any exits non-zero.
    public var failures: [String]

    public init(lines: [String] = [], notes: [String] = [], written: [String] = [], failures: [String] = []) {
        self.lines = lines
        self.notes = notes
        self.written = written
        self.failures = failures
    }

    /// Whether any file was rewritten.
    public var changed: Bool {
        !written.isEmpty
    }
}
