// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What `footprint --noCategories -p <pid> …` printed.
public enum FootprintReport {
    /// The memory footprint of each process the report headed, in megabytes by pid.
    public static func megabytes(parsing output: String) -> [Int32: Double] {
        var result: [Int32: Double] = [:]
        for line in output.split(separator: "\n") {
            guard let match = line.firstMatch(of: header), let pid = Int32(match.1), let value = Double(match.2) else { continue }
            let factor: Double = switch match.3 {
            case "B": 1.0 / 1_048_576
            case "KB": 1.0 / 1024
            case "MB": 1
            default: 1024
            }
            result[pid] = value * factor
        }
        return result
    }

    /// A process heading: `name [pid]: 64-bit    Footprint: 411 MB (16384 bytes per page)`.
    nonisolated(unsafe) private static let header = /\[(\d+)\]: \d+-bit\s+Footprint: ([0-9.]+) (B|KB|MB|GB)\b/
}
