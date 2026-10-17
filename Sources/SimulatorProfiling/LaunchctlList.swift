// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What `launchctl list` printed inside a simulator.
public enum LaunchctlList {
    /// The label of every running job by its pid; a job whose PID column is `-` is not running and is left out.
    public static func runningLabels(parsing output: String) -> [Int32: String] {
        var labels: [Int32: String] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, let pid = Int32(fields[0]) else { continue }
            labels[pid] = String(fields[2])
        }
        return labels
    }
}
