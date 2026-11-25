// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the paired stock and slim timing check that runs after the bisection.
struct PairedTimingTests {
    private func trial(launch: Double?, test: Double?) -> TrialMeasurement {
        var trial = TrialMeasurement(bootSeconds: 30)
        trial.launchSeconds = launch
        trial.uiTestSeconds = test
        return trial
    }

    private func pair(stock: Double, slim: Double) -> (stock: TrialMeasurement, slim: TrialMeasurement) {
        (trial(launch: 2, test: stock), trial(launch: 2, test: slim))
    }

    @Test func `the gamed regression under load fails although evaluate passes it`() {
        // Stock boots of 80 to 120 s under load: evaluate's limit is 120 × 1.3 + 10 = 166 s, so a slim 100 s test passes it.
        var floor = TrialMeasurement(bootSeconds: 30)
        floor.launchSeconds = 2
        floor.uiTestSeconds = 120
        var slim = trial(launch: 2, test: 100)
        slim.readBack = ["x"]
        #expect(HealthCheck.evaluate(trial: slim, baseline: floor, disabled: ["x"]).isEmpty)

        let pairs = [pair(stock: 80, slim: 100), pair(stock: 81, slim: 101)]

        #expect(HealthCheck.slowerInEveryPair(pairs, installing: true) == ["ui-test-runner"])
    }

    @Test func `the gamed regression on a quiet machine fails`() {
        #expect(HealthCheck.slowerInEveryPair([pair(stock: 19, slim: 39), pair(stock: 19.5, slim: 38)], installing: true) == ["ui-test-runner"])
    }

    @Test func `one slow pair is noise`() {
        #expect(HealthCheck.slowerInEveryPair([pair(stock: 19, slim: 39), pair(stock: 24.1, slim: 21.5)], installing: true).isEmpty)
    }

    @Test func `the slim boots measured after the fix pass`() {
        #expect(HealthCheck.slowerInEveryPair([pair(stock: 24.1, slim: 19.0), pair(stock: 19.3, slim: 21.5)], installing: true).isEmpty)
    }

    @Test func `the tolerance is five seconds or a tenth of the stock time`() {
        #expect(HealthCheck.timingTolerance(stock: 19) == 5)
        #expect(HealthCheck.timingTolerance(stock: 80) == 8)
        #expect(HealthCheck.slowerInEveryPair([pair(stock: 19, slim: 24), pair(stock: 19, slim: 24)], installing: true).isEmpty)
        #expect(HealthCheck.slowerInEveryPair([pair(stock: 19, slim: 24.5), pair(stock: 19, slim: 24.5)], installing: true) == ["ui-test-runner"])
        #expect(HealthCheck.slowerInEveryPair([pair(stock: 80, slim: 88), pair(stock: 80, slim: 88)], installing: true).isEmpty)
        #expect(HealthCheck.slowerInEveryPair([pair(stock: 80, slim: 88.5), pair(stock: 80, slim: 88.5)], installing: true) == ["ui-test-runner"])
    }

    @Test func `a slower launch is named launch where no app is installed`() {
        let pairs = Array(repeating: (trial(launch: 2, test: nil), trial(launch: 12, test: nil)), count: 2)

        #expect(HealthCheck.slowerInEveryPair(pairs, installing: false) == ["launch"])
        #expect(HealthCheck.slowerInEveryPair(pairs, installing: true) == ["install-launch"])
    }

    @Test func `a step either boot did not time is not compared`() {
        let pairs = Array(repeating: (trial(launch: nil, test: 19), trial(launch: 2, test: 39)), count: 2)

        #expect(HealthCheck.slowerInEveryPair(pairs, installing: true) == ["ui-test-runner"])
        #expect(HealthCheck.slowerInEveryPair([], installing: true).isEmpty)
    }
}
