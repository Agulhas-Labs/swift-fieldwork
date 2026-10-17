// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The commands and the clock a ``CostSampler`` reads, so a test can drive it without a simulator.
public protocol SamplingSource {
    /// Seconds since the boot began.
    func elapsed() -> TimeInterval
    /// Returns once `seconds` have elapsed since the boot began.
    func wait(untilElapsed seconds: TimeInterval)
    /// The output of `ps -axo pid=,ppid=,time=,command=`.
    func processTable() throws -> String
    /// The output of `launchctl list` inside the device.
    func launchctlList() throws -> String
    /// The output of `footprint --noCategories` for `pids`.
    func footprint(pids: [Int32]) throws -> String
}

/// What one service cost over the window.
public struct ServiceCost: Sendable, Equatable {
    /// The CPU time its processes used, in seconds.
    public let cpuSeconds: Double
    /// The sum of its processes' largest footprints, in megabytes; nil where none was measured.
    public let peakFootprintMB: Double?

    public init(cpuSeconds: Double, peakFootprintMB: Double?) {
        self.cpuSeconds = cpuSeconds
        self.peakFootprintMB = peakFootprintMB
    }
}

/// What a sampling run saw.
public struct CostMeasurement: Sendable, Equatable {
    /// The cost of every label that was running at some sample.
    public let costs: [String: ServiceCost]
    /// The most processes the device's tree held at one sample.
    public let maxProcessCount: Int
    /// The samples taken of the process table.
    public let samples: Int
    /// The reads that failed and so left a hole in a sample.
    public let failures: Int

    public init(costs: [String: ServiceCost], maxProcessCount: Int, samples: Int, failures: Int) {
        self.costs = costs
        self.maxProcessCount = maxProcessCount
        self.samples = samples
        self.failures = failures
    }

    /// The running labels that are not in `inventory`, sorted.
    public func labelsOutside(_ inventory: Set<String>) -> [String] {
        costs.keys.filter { !inventory.contains($0) }.sorted()
    }

    /// The `count` costliest labels by CPU time, or by footprint where `byFootprint`, largest first and ties by label.
    public func top(_ count: Int, byFootprint: Bool) -> [(label: String, cost: ServiceCost)] {
        let ranked = costs.map { (label: $0.key, cost: $0.value) }.sorted { left, right in
            let (a, b) = byFootprint ? (left.cost.peakFootprintMB ?? 0, right.cost.peakFootprintMB ?? 0) : (left.cost.cpuSeconds, right.cost.cpuSeconds)
            return a == b ? left.label < right.label : a > b
        }
        return Array(ranked.prefix(count))
    }
}

/// Measures what each service of a booting device costs, from sampled process tables, `launchctl list` and footprints.
public struct CostSampler {
    public let udid: String
    /// How long to sample from the start of the boot, in seconds.
    public let window: Int
    /// Seconds between samples of the process table and `launchctl list`.
    public let interval: Int
    /// Seconds between footprint samples; a multiple of `interval`.
    public let footprintInterval: Int

    public init(udid: String, window: Int, interval: Int = 5, footprintInterval: Int = 30) {
        self.udid = udid
        self.window = window
        self.interval = interval
        self.footprintInterval = footprintInterval
    }

    /// Samples until the window ends and returns what each label cost.
    public func measure(using source: SamplingSource) -> CostMeasurement {
        var labelOfPid: [Int32: String] = [:]
        var cpuOfPid: [Int32: Double] = [:]
        var footprintOfPid: [Int32: Double] = [:]
        var maxProcessCount = 0
        var samples = 0
        var failures = 0
        let footprintEvery = max(1, footprintInterval / max(1, interval))
        var tick = 0
        while tick * interval <= window {
            source.wait(untilElapsed: TimeInterval(tick * interval))
            var tree: [Int32] = []
            do {
                let table = try ProcessTable(parsing: source.processTable())
                tree = table.tree(underLaunchdSimFor: udid)
                let members = Set(tree)
                for row in table.rows where members.contains(row.pid) {
                    cpuOfPid[row.pid] = max(cpuOfPid[row.pid] ?? 0, row.cpuSeconds)
                }
                maxProcessCount = max(maxProcessCount, tree.count)
                samples += 1
            } catch {
                failures += 1
            }
            do {
                try labelOfPid.merge(LaunchctlList.runningLabels(parsing: source.launchctlList())) { _, new in new }
            } catch {
                failures += 1
            }
            if tick % footprintEvery == 0, !tree.isEmpty {
                do {
                    for (pid, megabytes) in try FootprintReport.megabytes(parsing: source.footprint(pids: tree)) {
                        footprintOfPid[pid] = max(footprintOfPid[pid] ?? 0, megabytes)
                    }
                } catch {
                    failures += 1
                }
            }
            tick += 1
        }
        var cpu: [String: Double] = [:]
        var footprint: [String: Double] = [:]
        for (pid, label) in labelOfPid {
            cpu[label, default: 0] += cpuOfPid[pid] ?? 0
            if let megabytes = footprintOfPid[pid] {
                footprint[label, default: 0] += megabytes
            }
        }
        let costs = cpu.reduce(into: [String: ServiceCost]()) { result, entry in
            result[entry.key] = ServiceCost(cpuSeconds: entry.value, peakFootprintMB: footprint[entry.key])
        }
        return CostMeasurement(costs: costs, maxProcessCount: maxProcessCount, samples: samples, failures: failures)
    }
}
