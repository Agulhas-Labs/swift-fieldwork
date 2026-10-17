// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorServices
import Testing

/// A profile is the measured answer for one runtime: it decodes only in a format this library knows, and plans what to switch off.
struct ServiceProfileTests {
    private func profile() throws -> ServiceProfile {
        try JSONDecoder().decode(ServiceProfile.self, from: Data(contentsOf: fixture("profile.json")))
    }

    @Test
    func decodesTheDocumentedShape() throws {
        let profile = try profile()
        #expect(profile.runtime.build == "24A434")
        #expect(profile.method.checks.count == 6)
        #expect(profile.services.count == 4)
        #expect(profile.services[3].peakFootprintMB == nil)
        #expect(profile.services[3].disposition == .notRunning)
        #expect(profile.labels(for: .healthKit) == ["com.example.healthd"])
        #expect(profile.labels(for: .iCloud).isEmpty)
    }

    @Test
    func roundTripsThroughJSON() throws {
        let original = try profile()
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ServiceProfile.self, from: data) == original)
        #expect((String(bytes: data, encoding: .utf8) ?? "").contains("\"healthKit\""))
    }

    @Test
    func disabledLabelsAreTheDisableDispositionsSorted() throws {
        #expect(try profile().disabledLabels == ["com.example.gizmod", "com.example.healthd"])
    }

    @Test
    func planWithNothingKeptDisablesEverything() throws {
        let plan = try profile().plan(keeping: [])
        #expect(plan.disabled == ["com.example.gizmod", "com.example.healthd"])
        #expect(plan.kept.isEmpty)
    }

    @Test
    func aKeptCapabilityLeavesTheDisabledListAndIsReported() throws {
        let plan = try profile().plan(keeping: [.healthKit, .iCloud])
        #expect(plan.disabled == ["com.example.gizmod"])
        #expect(plan.kept == [.healthKit: ["com.example.healthd"]])
    }

    @Test
    func aNewerSchemaIsRefused() throws {
        let text = try String(contentsOf: fixture("profile.json"), encoding: .utf8).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
        #expect(throws: SimulatorServicesError.unsupportedSchema(found: 2, supported: 1)) {
            try JSONDecoder().decode(ServiceProfile.self, from: Data(text.utf8))
        }
    }

    @Test
    func noProfileIsBundledYet() {
        #expect(ServiceProfiles.profile(forRuntime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0") == nil)
    }
}
