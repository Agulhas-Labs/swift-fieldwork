// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One row of `ps -axo pid=,ppid=,time=,command=`.
public struct ProcessRow: Sendable, Equatable {
    public let pid: Int32
    public let parent: Int32
    /// Cumulative CPU time, in seconds.
    public let cpuSeconds: Double
    public let command: String

    public init(pid: Int32, parent: Int32, cpuSeconds: Double, command: String) {
        self.pid = pid
        self.parent = parent
        self.cpuSeconds = cpuSeconds
        self.command = command
    }
}

/// The host's process table, as one `ps` run printed it.
public struct ProcessTable: Sendable, Equatable {
    public let rows: [ProcessRow]

    public init(rows: [ProcessRow]) {
        self.rows = rows
    }

    /// Parses `ps -axo pid=,ppid=,time=,command=` output; a line that does not have the four fields is skipped.
    public init(parsing output: String) {
        rows = output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let parent = Int32(fields[1]), let cpu = Self.cpuSeconds(fromTime: String(fields[2])) else {
                return nil
            }
            return ProcessRow(pid: pid, parent: parent, cpuSeconds: cpu, command: String(fields[3]))
        }
    }

    /// Seconds in a `ps` time column, `[[dd-]hh:]mm:ss[.ss]`; nil where the text is not one.
    public static func cpuSeconds(fromTime text: String) -> Double? {
        var rest = Substring(text)
        var days = 0.0
        if let dash = rest.firstIndex(of: "-") {
            guard let value = Double(rest[..<dash]) else { return nil }
            days = value
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":", omittingEmptySubsequences: false)
        guard (2 ... 3).contains(parts.count) else { return nil }
        var total = days * 86400
        for (index, part) in parts.reversed().enumerated() {
            guard let value = Double(part), value >= 0 else { return nil }
            total += value * [1.0, 60, 3600][index]
        }
        return total
    }

    /// The `launchd_sim` process of the device `udid` and every process below it, the root included; empty where the device has none.
    public func tree(underLaunchdSimFor udid: String) -> [Int32] {
        guard let root = rows.first(where: { row in Self.isLaunchdSim(row.command) && row.command.contains(udid) }) else { return [] }
        var children: [Int32: [Int32]] = [:]
        for row in rows {
            children[row.parent, default: []].append(row.pid)
        }
        var found: [Int32] = []
        var seen: Set<Int32> = []
        var pending = [root.pid]
        while let pid = pending.popLast() {
            guard seen.insert(pid).inserted else { continue }
            found.append(pid)
            pending.append(contentsOf: children[pid] ?? [])
        }
        return found.sorted()
    }

    private static func isLaunchdSim(_ command: String) -> Bool {
        let program = command.prefix(while: { character in character != " " })
        return program == "launchd_sim" || program.hasSuffix("/launchd_sim")
    }
}
