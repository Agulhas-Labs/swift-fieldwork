// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation

/// What a booted simulator holds in memory: the processes of its `launchd_sim` tree, the root included, and their summed `footprint`.
public struct DeviceMemory: Sendable, Equatable {
    /// The number of processes in the device's tree.
    public let processes: Int
    /// The tree's summed footprint, in megabytes. A process that exits between the table and the footprint read is left out.
    public let footprintMB: Double

    /// Reads a device's memory from the output of `ps -axo pid=,ppid=,time=,command=` and a closure that returns `footprint --noCategories` output for the pids it is given.
    ///
    /// Returns nil when the device has no `launchd_sim` in the table, which is a device that is not booted. The closure receives exactly the tree's pids; a process it reports nothing for counts in `processes` and adds nothing to the footprint.
    public init?(udid: String, processTable: String, footprint: ([Int32]) throws -> String) rethrows {
        let tree = ProcessTable(parsing: processTable).tree(underLaunchdSimFor: udid)
        guard !tree.isEmpty else { return nil }
        processes = tree.count
        footprintMB = try FootprintReport.megabytes(parsing: footprint(tree)).values.reduce(0, +)
    }

    /// Measures the device now, with `ps` and `footprint`: nil when it is not booted.
    ///
    /// A process that exits between the two reads makes `footprint` complain and still report the rest, so its standard output is used whatever the exit status; it throws only when `footprint` printed nothing, or `ps` failed.
    public static func measure(udid: String) throws -> DeviceMemory? {
        let table = try Subprocess.run("/bin/ps", ["-axo", "pid=,ppid=,time=,command="], deadline: 20)
        guard table.succeeded else {
            throw SimulatorServicesError.commandFailed(command: "ps", standardError: table.standardError)
        }
        return try DeviceMemory(udid: udid, processTable: table.standardOutput) { pids in
            let arguments = ["--noCategories"] + pids.flatMap { ["-p", String($0)] }
            let output = try Subprocess.run("/usr/bin/footprint", arguments, deadline: 60)
            guard !output.standardOutput.isEmpty else {
                throw SimulatorServicesError.commandFailed(command: "footprint", standardError: output.standardError)
            }
            return output.standardOutput
        }
    }
}
