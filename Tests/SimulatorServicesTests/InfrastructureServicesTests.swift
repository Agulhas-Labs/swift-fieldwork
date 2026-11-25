// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SimulatorServices
import Testing

/// Covers the stem match that names the services every app needs.
struct InfrastructureServicesTests {
    @Test func `a stem matches itself and its dotted children only`() {
        #expect(InfrastructureServices.matches("com.apple.lsd"))
        #expect(InfrastructureServices.matches("com.apple.mobile.installd.helper"))
        #expect(InfrastructureServices.matches("com.apple.dt"))
        #expect(InfrastructureServices.matches("com.apple.dt.instruments.dtsecurity"))
        #expect(!InfrastructureServices.matches("com.apple.dtrace"))
        #expect(!InfrastructureServices.matches("com.apple.lsdx"))
        #expect(!InfrastructureServices.matches("com.apple.weatherd"))
    }

    @Test func `the list holds the thirty-three stems`() {
        #expect(InfrastructureServices.stems.count == 33)
        #expect(Set(InfrastructureServices.stems).count == 33)
    }

    @Test(arguments: ["com.apple.CoreSimulator.SimRuntime.iOS-27-0", "com.apple.CoreSimulator.SimRuntime.iOS-27-2"])
    func `no bundled profile switches an infrastructure service off`(runtime: String) throws {
        let profile = try #require(ServiceProfiles.profile(forRuntime: runtime))
        #expect(profile.disabledLabels.filter(InfrastructureServices.matches).isEmpty)
        #expect(!profile.disabledLabels.contains("com.apple.gamed"))
    }

    @Test func `the new disposition is written as its name`() throws {
        #expect(try String(data: JSONEncoder().encode([Disposition.infrastructure]), encoding: .utf8) == "[\"infrastructure\"]")
    }
}
