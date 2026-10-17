// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorServices
import Testing

/// A capability's labels are those whose name is a rule's stem or continues it after a dot.
struct CapabilityTests {
    private func jobs(_ labels: [String]) -> [LaunchJob] {
        labels.map { LaunchJob(label: $0, domain: .daemon, start: .onDemand, program: nil) }
    }

    @Test
    func aStemMatchesItselfAndDotContinuations() {
        let found = Capability.labels(for: .healthKit, in: jobs(["com.apple.healthd", "com.apple.healthd.sync", "com.apple.other"]))
        #expect(found == ["com.apple.healthd", "com.apple.healthd.sync"])
    }

    @Test
    func aLongerNameWithoutADotBoundaryDoesNotMatch() {
        #expect(Capability.labels(for: .healthKit, in: jobs(["com.apple.healthdx"])).isEmpty)
    }

    @Test
    func pushMatchesOnlyTheExactDaemon() {
        let found = Capability.labels(for: .pushNotifications, in: jobs(["com.apple.apsd", "com.apple.apsd.tcpdump.en0", "com.apple.apsd.tcpdump"]))
        #expect(found == ["com.apple.apsd"])
    }

    @Test
    func resultsAreSorted() {
        let found = Capability.labels(for: .photos, in: jobs(["com.apple.photosface", "com.apple.assetsd", "com.apple.cloudphotod"]))
        #expect(found == ["com.apple.assetsd", "com.apple.cloudphotod", "com.apple.photosface"])
    }

    @Test
    func contactsStemCoversItsSubservices() {
        #expect(Capability.labels(for: .contacts, in: jobs(["com.apple.contacts.postersyncd", "com.apple.contactsd"])) == ["com.apple.contacts.postersyncd", "com.apple.contactsd"])
    }

    @Test
    func everyCapabilityHasAtLeastOneRule() {
        let probes: [Capability: String] = [
            .healthKit: "com.apple.healthd", .pushNotifications: "com.apple.apsd", .iCloud: "com.apple.cloudd", .associatedDomains: "com.apple.swcd",
            .storeKit: "com.apple.storekitd", .contacts: "com.apple.contactsd", .calendars: "com.apple.calaccessd", .photos: "com.apple.assetsd",
            .reminders: "com.apple.remindd",
        ]
        #expect(probes.count == Capability.allCases.count)
        for (capability, label) in probes {
            #expect(Capability.labels(for: capability, in: jobs([label])) == [label])
        }
    }
}
