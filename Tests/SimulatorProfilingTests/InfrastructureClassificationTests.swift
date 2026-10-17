// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import SimulatorServices
import Testing

/// Covers the rule that keeps the services every app needs out of the candidates.
struct InfrastructureClassificationTests {
    @Test func `an on-demand infrastructure service is never a candidate, whatever it costs`() {
        let jobs = [
            LaunchJob(label: "com.apple.lsd", domain: .daemon, start: .onDemand, program: nil),
            LaunchJob(label: "com.apple.dt.xctest.service", domain: .daemon, start: .other, program: nil),
            LaunchJob(label: "com.apple.lsdx", domain: .daemon, start: .onDemand, program: nil),
            LaunchJob(label: "com.apple.tccd", domain: .daemon, start: .onDemand, program: nil),
            LaunchJob(label: "com.apple.weatherd", domain: .daemon, start: .onDemand, program: nil),
            LaunchJob(label: "com.apple.securityd", domain: .daemon, start: .keepAlive, program: nil),
            LaunchJob(label: "com.apple.installd.never", domain: .daemon, start: .onDemand, program: nil),
        ]
        let heavy = ServiceCost(cpuSeconds: 9, peakFootprintMB: 90)
        let cost = [
            "com.apple.lsd": heavy, "com.apple.dt.xctest.service": heavy, "com.apple.lsdx": heavy,
            "com.apple.tccd": ServiceCost(cpuSeconds: 0, peakFootprintMB: 0.1), "com.apple.weatherd": heavy, "com.apple.securityd": heavy,
        ]

        let entries = Dispositions.classify(jobs: jobs, cost: cost, footprintThresholdMB: 4, cpuThresholdSeconds: 0.5)
        let byLabel = Dictionary(uniqueKeysWithValues: entries.map { ($0.label, $0.disposition) })

        #expect(byLabel["com.apple.lsd"] == .infrastructure)
        #expect(byLabel["com.apple.dt.xctest.service"] == .infrastructure)
        #expect(byLabel["com.apple.lsdx"] == .disable)
        #expect(byLabel["com.apple.tccd"] == .infrastructure)
        #expect(byLabel["com.apple.weatherd"] == .disable)
        #expect(byLabel["com.apple.securityd"] == .core)
        #expect(byLabel["com.apple.installd.never"] == .notRunning)
    }
}
