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

    @Test func `the list holds the thirty-two stems`() {
        #expect(InfrastructureServices.stems.count == 32)
        #expect(Set(InfrastructureServices.stems).count == 32)
    }

    @Test func `the new disposition is written as its name`() throws {
        #expect(try String(data: JSONEncoder().encode([Disposition.infrastructure]), encoding: .utf8) == "[\"infrastructure\"]")
    }
}
