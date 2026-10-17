// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers what counts as a respawn: a running job whose pid changed and whose last exit was a crash.
struct RespawnRuleTests {
    @Test func `launchctl list parses pid and status and skips the header`() {
        let text = "PID\tStatus\tLabel\n101\t0\tcom.example.one\n-\t-9\tcom.example.two\n-\t1\tcom.example.three\n"

        let jobs = LaunchctlList.jobs(parsing: text)

        #expect(jobs.count == 3)
        #expect(jobs["com.example.one"] == LaunchctlJob(pid: 101, status: 0))
        #expect(jobs["com.example.two"] == LaunchctlJob(pid: nil, status: -9))
        #expect(jobs["com.example.three"] == LaunchctlJob(pid: nil, status: 1))
    }

    private func respawned(status: Int32, afterPid: Int32? = 202) -> Set<String> {
        TrialRunner.respawned(
            before: ["a": LaunchctlJob(pid: 101, status: 0)],
            after: ["a": LaunchctlJob(pid: afterPid, status: status)]
        )
    }

    @Test func `a clean exit or a launchd kill is not a respawn`() {
        #expect(respawned(status: 0).isEmpty)
        #expect(respawned(status: -9).isEmpty)
        #expect(respawned(status: -15).isEmpty)
    }

    @Test func `a crash signal or an exit code is a respawn`() {
        #expect(respawned(status: -11) == ["a"])
        #expect(respawned(status: 1) == ["a"])
    }

    @Test func `the same pid is not a respawn`() {
        #expect(respawned(status: -11, afterPid: 101).isEmpty)
    }

    @Test func `a job running before and stopped after with a crash status is a respawn`() {
        #expect(respawned(status: -6, afterPid: nil) == ["a"])
    }

    @Test func `a job not running before is not a respawn`() {
        let result = TrialRunner.respawned(
            before: ["a": LaunchctlJob(pid: nil, status: 0)],
            after: ["a": LaunchctlJob(pid: 5, status: -11)]
        )
        #expect(result.isEmpty)
    }
}
