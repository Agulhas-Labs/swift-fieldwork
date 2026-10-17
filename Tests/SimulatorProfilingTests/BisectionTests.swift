// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the search for the services a device needs, against a scripted failure rule.
struct BisectionTests {
    private final class Trials: @unchecked Sendable {
        var sets: [[String]] = []
    }

    /// Runs the search where a set fails when it holds all of one of `culprits` (each a group that fails only together).
    private func search(_ candidates: [String], culprits: [Set<String>], maxKept: Int = 12) throws -> (kept: [String], trials: Int) {
        let trials = Trials()
        let kept = try Bisection.kept(candidates: candidates, maxKept: maxKept) { set in
            trials.sets.append(set)
            return culprits.contains { $0.isSubset(of: set) }
        }
        return (kept, trials.sets.count)
    }

    private let letters = ["a", "b", "c", "d", "e", "f", "g", "h"]

    @Test func `no culprit keeps nothing after one trial`() throws {
        let result = try search(letters, culprits: [])

        #expect(result.kept.isEmpty)
        #expect(result.trials == 1)
    }

    @Test func `one culprit is found by halving`() throws {
        let result = try search(letters, culprits: [["f"]])

        #expect(result.kept == ["f"])
        #expect(result.trials == 5)
    }

    @Test func `two culprits are both kept`() throws {
        let result = try search(letters, culprits: [["b"], ["g"]])

        #expect(result.kept == ["b", "g"])
    }

    @Test func `a pair that fails only together is kept by its later member`() throws {
        let result = try search(letters, culprits: [["c", "e"]])

        #expect(result.kept == ["e"])
    }

    @Test func `candidates are tried sorted and without repeats`() throws {
        let trials = Trials()
        _ = try Bisection.kept(candidates: ["b", "a", "b"]) { set in
            trials.sets.append(set)
            return false
        }

        #expect(trials.sets == [["a", "b"]])
    }

    @Test func `more culprits than the cap throws`() {
        #expect(throws: BisectionError(maxKept: 2)) {
            try search(letters, culprits: [["a"], ["b"], ["c"]], maxKept: 2)
        }
    }

    @Test func `exactly the cap is allowed`() throws {
        let result = try search(letters, culprits: [["a"], ["b"]], maxKept: 2)

        #expect(result.kept == ["a", "b"])
    }

    @Test func `a failing trial that throws ends the search`() {
        struct Broken: Error {}

        #expect(throws: Broken.self) {
            try Bisection.kept(candidates: ["a"]) { _ in throw Broken() }
        }
    }
}
