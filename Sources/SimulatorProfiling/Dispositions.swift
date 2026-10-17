// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SimulatorServices

/// Decides what to do about each service of a runtime from what it cost.
public enum Dispositions {
    /// One entry per job, sorted by label.
    ///
    /// A job that never ran is `notRunning`; one that ran and starts at boot is `core`; one that ran, starts on demand and is infrastructure is `infrastructure`; one that ran and starts on demand is a `disable` candidate when it costs at least a threshold, and `belowThreshold` otherwise.
    public static func classify(
        jobs: [LaunchJob],
        cost: [String: ServiceCost],
        footprintThresholdMB: Double,
        cpuThresholdSeconds: Double
    ) -> [ServiceEntry] {
        jobs.sorted { $0.label < $1.label }.map { job in
            guard let measured = cost[job.label] else {
                return ServiceEntry(label: job.label, domain: job.domain, start: job.start, ranAtBoot: false, peakFootprintMB: nil, cpuSeconds: nil, disposition: .notRunning)
            }
            let disposition: Disposition
            switch job.start {
            case .keepAlive, .atLoad:
                disposition = .core
            case .onDemand, .other:
                let heavy = (measured.peakFootprintMB ?? 0) >= footprintThresholdMB || measured.cpuSeconds >= cpuThresholdSeconds
                if InfrastructureServices.matches(job.label) {
                    disposition = .infrastructure
                } else {
                    disposition = heavy ? .disable : .belowThreshold
                }
            }
            return ServiceEntry(
                label: job.label, domain: job.domain, start: job.start, ranAtBoot: true,
                peakFootprintMB: measured.peakFootprintMB, cpuSeconds: measured.cpuSeconds, disposition: disposition
            )
        }
    }
}
