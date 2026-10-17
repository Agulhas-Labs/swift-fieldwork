// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import SimulatorServices
import Testing

@Suite("Capabilities kept on for the input")
struct KeepCapabilityTests {
    private let base = ["--runtime", "r", "--device-type", "d", "--out", "p.json"]

    private let profile = ServiceProfile(
        profileVersion: 1,
        runtime: ProfileRuntime(identifier: "r", version: "27.0", build: "1A1"),
        deviceType: "d",
        generated: "2026-01-01",
        method: ProfileMethod(costWindowSeconds: 30, footprintThresholdMB: 4, cpuThresholdSeconds: 0.5, checks: []),
        services: [],
        capabilities: [.healthKit: ["h.one", "h.two"], .iCloud: ["i.one"]]
    )

    @Test func `keep takes capability names`() throws {
        let options = try ProfileOptions.parse(base + ["--keep", "healthKit,iCloud"])
        #expect(options.keep == [.healthKit, .iCloud])
    }

    @Test func `an unknown capability is refused and the valid ones listed`() {
        let valid = "healthKit, pushNotifications, iCloud, associatedDomains, storeKit, contacts, calendars, photos, reminders"
        #expect(throws: ProfileUsageError(message: "--keep names bogus, which is not a capability; the capabilities are \(valid)")) {
            try ProfileOptions.parse(base + ["--keep", "bogus"])
        }
    }

    @Test func `the labels of a kept capability leave the candidates`() {
        let left = HealthStage.candidates(["h.one", "x.y", "i.one", "h.two", "z.w"], keeping: [.healthKit], in: profile)
        #expect(left == ["x.y", "i.one", "z.w"])
    }

    @Test func `a profile written before the field decodes with none`() throws {
        let json = #"{"costWindowSeconds":30,"footprintThresholdMB":4,"cpuThresholdSeconds":0.5,"checks":["boot"]}"#
        let method = try JSONDecoder().decode(ProfileMethod.self, from: Data(json.utf8))
        #expect(method.keptForInput.isEmpty)
    }

    @Test func `the field survives a round trip`() throws {
        let method = ProfileMethod(costWindowSeconds: 30, footprintThresholdMB: 4, cpuThresholdSeconds: 0.5, checks: [], keptForInput: ["healthKit"])
        let decoded = try JSONDecoder().decode(ProfileMethod.self, from: JSONEncoder().encode(method))
        #expect(decoded == method)
    }
}
