// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Keeps what one agent's installer printed, so the tool's `install` command can print it under that agent's name and gather the lines every installer repeats into one summary.
///
/// Locked because the consumer's output closures are `@Sendable`.
public final class InstallCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [String] = []

    public init() {}

    /// Every line printed, in order, stderr's among them: a line printed as several is split into several.
    public var lines: [String] {
        lock.withLock { captured }
    }

    /// Keeps `text`, split into lines.
    public func keep(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lock.withLock { captured += lines }
    }
}
