// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Counts what `log show --style ndjson` printed.
public enum LogCounts {
    /// The number of lines by the basename of the process that wrote them; a line that is not a JSON object with a `processImagePath` is not counted.
    public static func count(ndjson text: String) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("{") {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let path = object["processImagePath"] as? String, !path.isEmpty
            else { continue }
            counts[(path as NSString).lastPathComponent, default: 0] += 1
        }
        return counts
    }
}
