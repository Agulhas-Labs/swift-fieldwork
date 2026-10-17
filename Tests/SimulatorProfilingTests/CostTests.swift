// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import SimulatorServices
import Testing

/// Covers the sampler against a scripted source, and the rule that turns costs into dispositions.
struct CostTests {
    private struct ReadFailure: Error {}

    /// A source that answers each read from a script, one entry per call, and the last entry for every call after.
    private final class ScriptedSource: SamplingSource {
        var processTables: [String]
        var launchctlLists: [String?]
        var footprints: [String]
        var waits: [TimeInterval] = []
        private var calls = (process: 0, launchctl: 0, footprint: 0)

        init(processTables: [String], launchctlLists: [String?], footprints: [String]) {
            self.processTables = processTables
            self.launchctlLists = launchctlLists
            self.footprints = footprints
        }

        func elapsed() -> TimeInterval {
            waits.last ?? 0
        }

        func wait(untilElapsed seconds: TimeInterval) {
            waits.append(seconds)
        }

        func processTable() throws -> String {
            defer { calls.process += 1 }
            return processTables[min(calls.process, processTables.count - 1)]
        }

        func launchctlList() throws -> String {
            defer { calls.launchctl += 1 }
            guard let text = launchctlLists[min(calls.launchctl, launchctlLists.count - 1)] else { throw ReadFailure() }
            return text
        }

        func footprint(pids _: [Int32]) throws -> String {
            defer { calls.footprint += 1 }
            return footprints[min(calls.footprint, footprints.count - 1)]
        }
    }

    private func table(_ udid: String, _ children: [(pid: Int, time: String)]) -> String {
        (["10 1 0:00.10 launchd_sim /Devices/\(udid)/data/launchd_bootstrap.plist"]
            + children.map { "\($0.pid) 10 \($0.time) /RT/usr/libexec/daemon\($0.pid)" }).joined(separator: "\n")
    }

    private func footprint(_ megabytes: [Int: Int]) -> String {
        megabytes.sorted { $0.key < $1.key }.map { "p [\($0.key)]: 64-bit    Footprint: \($0.value) MB (16384 bytes per page)" }.joined(separator: "\n")
    }

    private func scenario(_ udid: String) -> ScriptedSource {
        ScriptedSource(
            processTables: [
                table(udid, []),
                table(udid, [(11, "0:00.50"), (12, "0:00.20")]),
                table(udid, [(11, "0:02.50"), (13, "0:01.00")]),
                table(udid, [(11, "0:03.00"), (13, "0:01.00")]),
                table(udid, [(11, "0:02.00"), (13, "0:00.50")]),
            ],
            launchctlLists: [
                nil,
                "PID\tStatus\tLabel\n11\t0\tcom.example.a\n12\t0\tcom.example.b\n-\t0\tcom.example.idle",
                "PID\tStatus\tLabel\n11\t0\tcom.example.a\n13\t0\tcom.example.a",
            ],
            footprints: [footprint([10: 2]), footprint([11: 8, 13: 5]), footprint([11: 6, 13: 9, 10: 3])]
        )
    }

    @Test func `a label costs the sum of its processes' largest CPU time and footprint`() {
        let udid = UUID().uuidString
        let measurement = CostSampler(udid: udid, window: 20, footprintInterval: 10).measure(using: scenario(udid))

        #expect(measurement.costs["com.example.a"] == ServiceCost(cpuSeconds: 4.0, peakFootprintMB: 17))
        #expect(measurement.costs["com.example.b"] == ServiceCost(cpuSeconds: 0.2, peakFootprintMB: nil))
        #expect(measurement.costs["com.example.idle"] == nil)
    }

    @Test func `the sampler reads at the interval from the start of the boot and counts what it saw`() {
        let udid = UUID().uuidString
        let source = scenario(udid)

        let measurement = CostSampler(udid: udid, window: 20, footprintInterval: 10).measure(using: source)

        #expect(source.waits == [0, 5, 10, 15, 20])
        #expect(measurement.samples == 5)
        #expect(measurement.maxProcessCount == 3)
        #expect(measurement.failures == 1)
    }

    @Test func `labels outside the inventory are listed, and the costliest come first`() {
        let udid = UUID().uuidString
        let measurement = CostSampler(udid: udid, window: 20, footprintInterval: 10).measure(using: scenario(udid))

        #expect(measurement.labelsOutside(["com.example.a"]) == ["com.example.b"])
        #expect(measurement.top(1, byFootprint: false).map(\.label) == ["com.example.a"])
        #expect(measurement.top(2, byFootprint: true).map(\.label) == ["com.example.a", "com.example.b"])
    }

    @Test func `each kind of job lands on its own disposition`() {
        let jobs = [
            LaunchJob(label: "z.never", domain: .daemon, start: .onDemand, program: nil),
            LaunchJob(label: "a.core", domain: .daemon, start: .keepAlive, program: nil),
            LaunchJob(label: "b.atload", domain: .agent, start: .atLoad, program: nil),
            LaunchJob(label: "c.heavy", domain: .agent, start: .onDemand, program: nil),
            LaunchJob(label: "d.busy", domain: .agent, start: .other, program: nil),
            LaunchJob(label: "e.small", domain: .agent, start: .onDemand, program: nil),
            LaunchJob(label: "f.edge", domain: .daemon, start: .onDemand, program: nil),
        ]
        let cost = [
            "a.core": ServiceCost(cpuSeconds: 9, peakFootprintMB: 90),
            "b.atload": ServiceCost(cpuSeconds: 0, peakFootprintMB: 0.1),
            "c.heavy": ServiceCost(cpuSeconds: 0.1, peakFootprintMB: 12),
            "d.busy": ServiceCost(cpuSeconds: 3, peakFootprintMB: nil),
            "e.small": ServiceCost(cpuSeconds: 0.1, peakFootprintMB: 1),
            "f.edge": ServiceCost(cpuSeconds: 0.5, peakFootprintMB: 4),
        ]

        let entries = Dispositions.classify(jobs: jobs, cost: cost, footprintThresholdMB: 4, cpuThresholdSeconds: 0.5)

        #expect(entries.map(\.label) == ["a.core", "b.atload", "c.heavy", "d.busy", "e.small", "f.edge", "z.never"])
        #expect(entries.map(\.disposition) == [.core, .core, .disable, .disable, .belowThreshold, .disable, .notRunning])
        #expect(entries.map(\.ranAtBoot) == [true, true, true, true, true, true, false])
        #expect(entries[6].cpuSeconds == nil)
        #expect(entries[6].peakFootprintMB == nil)
        #expect(entries[2].peakFootprintMB == 12)
    }
}
