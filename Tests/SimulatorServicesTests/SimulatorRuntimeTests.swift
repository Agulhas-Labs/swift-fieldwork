// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorServices
import Testing

/// The runtime list is decoded from `simctl`'s JSON, ignoring what it does not need.
struct SimulatorRuntimeTests {
    @Test
    func parsesTheRuntimeList() throws {
        let runtimes = try SimulatorRuntime.parseList(Data(contentsOf: fixture("runtimes.json")))
        #expect(runtimes.count == 2)
        #expect(runtimes[0].identifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-0")
        #expect(runtimes[0].version == "27.0")
        #expect(runtimes[0].buildversion == "24A434")
        #expect(runtimes[0].runtimeRoot == "/example/RuntimeRoot")
        #expect(runtimes[0].isAvailable)
        #expect(!runtimes[1].isAvailable)
    }

    @Test
    func refusesJSONWithoutRuntimes() {
        #expect(throws: (any Error).self) { try SimulatorRuntime.parseList(Data("{}".utf8)) }
    }
}
