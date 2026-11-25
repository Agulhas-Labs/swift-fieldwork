// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import SimulatorServices
import Testing

/// `--install` writes the profile where `ServiceProfiles.resolve(forRuntime:)` finds it.
struct ProfileInstallTests {
    @Test
    func anInstalledProfileIsFoundAsLocal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("profile-install-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let identifier = "com.apple.CoreSimulator.SimRuntime.iOS-26-4"
        let base = try #require(ServiceProfiles.profile(forRuntime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0"))
        let profile = ServiceProfile(
            profileVersion: base.profileVersion,
            runtime: ProfileRuntime(identifier: identifier, version: "26.4", build: "build"),
            deviceType: base.deviceType,
            generated: base.generated,
            method: base.method,
            services: base.services,
            capabilities: base.capabilities
        )
        let environment = ["FIELDWORK_SERVICE_PROFILES": directory.appendingPathComponent("nested").path]

        let url = try ProfileInstall.install(profile, environment: environment)
        let again = try ProfileInstall.install(profile, environment: environment)

        #expect(url.lastPathComponent == "\(identifier).json")
        #expect(again == url)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == ["\(identifier).json"])
        guard case let .found(found, source) = ServiceProfiles.resolve(forRuntime: identifier, environment: environment) else {
            Issue.record("expected found")
            return
        }
        #expect(source == .local(url))
        #expect(found == profile)
    }
}
