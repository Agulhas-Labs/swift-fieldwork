// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import SimulatorProfiling
import Testing

@Suite("A noisy failure counts only when it recurs")
struct ConfirmedFailureTests {
    @Test("no failure needs no retry")
    func empty() {
        var retried = false
        let result = HealthCheck.confirmed([]) {
            retried = true
            return []
        }
        #expect(result.isEmpty)
        #expect(!retried)
    }

    @Test("a failure that is not noisy stands without a retry")
    func firm() {
        var retried = false
        let first: [HealthFailure] = [.installLaunch, .logFlood("a")]
        let result = HealthCheck.confirmed(first) {
            retried = true
            return []
        }
        #expect(result == first)
        #expect(!retried)
    }

    @Test("a flood that does not recur is dropped")
    func vanishes() {
        #expect(HealthCheck.confirmed([.logFlood("a")]) { [.logFlood("b")] }.isEmpty)
    }

    @Test("only the failures that recur remain")
    func partial() {
        #expect(HealthCheck.confirmed([.respawn("x"), .logFlood("y")]) { [.respawn("x")] } == [.respawn("x")])
    }

    @Test("failures that all recur all remain, in the first run's order")
    func all() {
        let both: [HealthFailure] = [.logFlood("a"), .respawn("b")]
        #expect(HealthCheck.confirmed(both) { both } == both)
    }
}
