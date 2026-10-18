// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension Subprocess.Output {
    /// What a failed run said, its error before its output: the first line, then each line of a `Caused by:` chain after it.
    ///
    /// A tool often puts the reason under its first line (`Error: failed to load configuration`, then `Caused by:` and the cause), so the first line alone names a failure without its cause.
    var failureReason: String {
        guard let said = [standardError, standardOutput].first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return "no output"
        }
        let lines = said.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var reason = [lines[0]]
        if let causes = lines.firstIndex(of: "Caused by:") {
            reason += lines[(causes + 1)...]
        }
        return reason.joined(separator: ": ")
    }
}
