// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the cap on the boots the health stage's bisection makes.
struct TrialBudgetTests {
    @Test func `the hundredth spend passes and the next throws`() throws {
        var budget = TrialBudget(limit: 100)
        for _ in 1 ... 100 {
            try budget.spend(keptSoFar: [])
        }

        #expect(throws: TrialBudgetError(limit: 100, keptSoFar: ["a"])) {
            try budget.spend(keptSoFar: ["a"])
        }
    }

    @Test func `the refusal names the limit and what was kept`() {
        #expect(TrialBudgetError(limit: 100, keptSoFar: ["a", "b"]).description == "the health stage stopped after 100 trials (--max-trials) without settling which services to keep; kept on so far: a, b; run again on a quieter machine or raise --max-trials")
        #expect(TrialBudgetError(limit: 5, keptSoFar: []).description.contains("kept on so far: none;"))
    }

    @Test func `the bisection reports each candidate as it keeps it`() throws {
        var reported: [String] = []
        let kept = try Bisection.kept(candidates: ["a", "b", "c"], onKept: { reported.append($0) }, fails: { $0.contains("b") })

        #expect(kept == ["b"])
        #expect(reported == ["b"])
    }

    @Test func `--max-trials is read, defaults to 100 and refuses 0`() throws {
        let base = ["--runtime", "r", "--device-type", "d", "--out", "o.json"]

        #expect(try ProfileOptions.parse(base).maxTrials == 100)
        #expect(try ProfileOptions.parse(base + ["--max-trials", "7"]).maxTrials == 7)
        #expect(throws: ProfileUsageError(message: "--max-trials needs a number of at least 1, not 0")) {
            try ProfileOptions.parse(base + ["--max-trials", "0"])
        }
    }
}
