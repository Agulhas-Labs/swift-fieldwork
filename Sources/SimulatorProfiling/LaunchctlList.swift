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

    /// Every job `launchctl list` printed by label, with its pid (nil where the PID column is `-`) and last exit status.
    ///
    /// A line whose status is not an integer, such as the header, is left out.
    public static func jobs(parsing output: String) -> [String: LaunchctlJob] {
        var jobs: [String: LaunchctlJob] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, let status = Int32(fields[1]) else { continue }
            jobs[String(fields[2])] = LaunchctlJob(pid: Int32(fields[0]), status: status)
        }
        return jobs
    }
}

/// One row of `launchctl list`.
public struct LaunchctlJob: Equatable, Sendable {
    /// The process id; nil where the job is not running.
    public let pid: Int32?
    /// The last exit status: 0 for a clean exit, a positive exit code, or a negative signal number.
    public let status: Int32

    public init(pid: Int32?, status: Int32) {
        self.pid = pid
        self.status = status
    }
}
