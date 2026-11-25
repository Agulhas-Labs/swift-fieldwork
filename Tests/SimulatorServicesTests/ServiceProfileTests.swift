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
    func theBundledIOS27ProfileDecodesAndSparesTheInfrastructure() throws {
        let profile = try #require(ServiceProfiles.profile(forRuntime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0"))

        #expect(profile.runtime.identifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        #expect(!profile.disabledLabels.isEmpty)
        #expect(profile.disabledLabels.filter(InfrastructureServices.matches).isEmpty)
    }

    private static let ios26 = "com.apple.CoreSimulator.SimRuntime.iOS-26-4"
    private static let ios27 = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"

    /// The bundled iOS 27.0 profile relabelled as another runtime's.
    private func relabelled(as identifier: String) throws -> ServiceProfile {
        let base = try #require(ServiceProfiles.profile(forRuntime: Self.ios27))
        return ServiceProfile(
            profileVersion: base.profileVersion,
            runtime: ProfileRuntime(identifier: identifier, version: base.runtime.version, build: base.runtime.build),
            deviceType: base.deviceType,
            generated: base.generated,
            method: base.method,
            services: base.services,
            capabilities: base.capabilities
        )
    }

    private func write(_ text: Data, named name: String, in directory: TemporaryDirectory) throws -> URL {
        let url = directory.url.appendingPathComponent("\(name).json")
        try text.write(to: url)
        return url
    }

    @Test
    func aRuntimeWithNoBundledProfileOrLocalFileHasNone() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let environment = ["FIELDWORK_SERVICE_PROFILES": directory.url.path]

        guard case .none = ServiceProfiles.resolve(forRuntime: Self.ios26, environment: environment) else {
            Issue.record("expected none")
            return
        }
    }

    @Test
    func aBundledProfileWinsOverALocalFileForTheSameRuntime() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        _ = try write(Data("garbage".utf8), named: Self.ios27, in: directory)

        let resolution = ServiceProfiles.resolve(forRuntime: Self.ios27, environment: ["FIELDWORK_SERVICE_PROFILES": directory.url.path])

        guard case let .found(_, source) = resolution else {
            Issue.record("expected found")
            return
        }
        #expect(source == .bundled)
    }

    @Test
    func aLocalFileServesARuntimeWithNoBundledProfile() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let profile = try relabelled(as: Self.ios26)
        let url = try write(JSONEncoder().encode(profile), named: Self.ios26, in: directory)

        let resolution = ServiceProfiles.resolve(forRuntime: Self.ios26, environment: ["FIELDWORK_SERVICE_PROFILES": directory.url.path])

        guard case let .found(found, source) = resolution else {
            Issue.record("expected found")
            return
        }
        #expect(source == .local(url))
        #expect(found.runtime.identifier == Self.ios26)
        #expect(resolution.profile == found)
    }

    @Test
    func aLocalFileThatDoesNotDecodeIsRefused() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let url = try write(Data("not json".utf8), named: Self.ios26, in: directory)

        let resolution = ServiceProfiles.resolve(forRuntime: Self.ios26, environment: ["FIELDWORK_SERVICE_PROFILES": directory.url.path])

        guard case let .unreadable(refused, _) = resolution else {
            Issue.record("expected unreadable")
            return
        }
        #expect(refused == url)
        #expect(resolution.profile == nil)
    }

    @Test
    func aLocalFileInANewerFormatIsRefused() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let text = try String(contentsOf: fixture("profile.json"), encoding: .utf8).replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2")
        _ = try write(Data(text.utf8), named: Self.ios26, in: directory)

        let resolution = ServiceProfiles.resolve(forRuntime: Self.ios26, environment: ["FIELDWORK_SERVICE_PROFILES": directory.url.path])

        guard case .unreadable = resolution else {
            Issue.record("expected unreadable")
            return
        }
    }

    @Test
    func aLocalFileForAnotherRuntimeIsRefused() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        _ = try write(JSONEncoder().encode(relabelled(as: Self.ios27)), named: Self.ios26, in: directory)

        let resolution = ServiceProfiles.resolve(forRuntime: Self.ios26, environment: ["FIELDWORK_SERVICE_PROFILES": directory.url.path])

        guard case let .unreadable(_, reason) = resolution else {
            Issue.record("expected unreadable")
            return
        }
        #expect(reason == "its runtime is com.apple.CoreSimulator.SimRuntime.iOS-27-0, not com.apple.CoreSimulator.SimRuntime.iOS-26-4")
    }

    @Test
    func theLocalDirectoryIsTheVariableWhenAbsoluteElseUnderHome() {
        #expect(ServiceProfiles.localDirectory(environment: ["FIELDWORK_SERVICE_PROFILES": "/tmp/profiles", "HOME": "/Users/x"]).path == "/tmp/profiles")
        #expect(ServiceProfiles.localDirectory(environment: ["FIELDWORK_SERVICE_PROFILES": "relative/dir", "HOME": "/Users/x"]).path == "/Users/x/.config/fieldwork/service-profiles")
        #expect(ServiceProfiles.localDirectory(environment: ["HOME": "/Users/x"]).path == "/Users/x/.config/fieldwork/service-profiles")
    }
}
