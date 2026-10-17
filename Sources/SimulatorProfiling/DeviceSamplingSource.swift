// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation

/// A ``SamplingSource`` that runs the real commands against a booting device.
public struct DeviceSamplingSource: SamplingSource, Sendable {
    private let device: ProfileDevice
    private let started: TimeInterval

    /// Starts the clock now.
    public init(device: ProfileDevice) {
        self.device = device
        started = ProcessInfo.processInfo.systemUptime
    }

    public func elapsed() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime - started
    }

    public func wait(untilElapsed seconds: TimeInterval) {
        let remaining = seconds - elapsed()
        if remaining > 0 {
            Thread.sleep(forTimeInterval: remaining)
        }
    }

    public func processTable() throws -> String {
        try Self.output(of: Subprocess.run("/bin/ps", ["-axo", "pid=,ppid=,time=,command="], deadline: 20), command: "ps")
    }

    public func launchctlList() throws -> String {
        try Self.output(of: device.spawn(["launchctl", "list"], deadline: 20), command: "launchctl list")
    }

    /// A process that exits between the tree and the call makes `footprint` complain and still report the rest, so its standard output is used whatever the exit status.
    public func footprint(pids: [Int32]) throws -> String {
        let arguments = ["--noCategories"] + pids.flatMap { ["-p", String($0)] }
        let output = try Subprocess.run("/usr/bin/footprint", arguments, deadline: 60)
        guard !output.standardOutput.isEmpty else {
            throw ProfileDeviceError(command: "footprint", detail: output.standardError)
        }
        return output.standardOutput
    }

    private static func output(of result: Subprocess.Output, command: String) throws -> String {
        guard result.succeeded else { throw ProfileDeviceError(command: command, detail: result.standardError) }
        return result.standardOutput
    }
}
