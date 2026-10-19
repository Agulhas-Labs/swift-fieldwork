// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// What a probe leaves behind: no process from a child stopped at its deadline, and no scratch directory once it is released.
struct DoctorProbeLifecycleTests {
    /// Every grandchild's command line holds this, so a stray one can be found by it.
    private static let marker = "fieldwork-doctor-orphan"

    /// `script` run by the default launcher with a one-second limit, where it starts a grandchild that writes its pid to `pidFile` and then loops: the launch's answer and the grandchild's pid.
    private static func launch(_ script: (_ grandchild: String) -> String, pidFile: URL) throws -> (answer: (status: Int32, output: Data)?, grandchild: pid_t) {
        let loop = "trap '' TERM; echo $$ > \(ShellWord.quoted(pidFile.path)); while :; do sleep 0.2; done"
        let grandchild = "sh -c \(ShellWord.quoted(loop)) \(marker)"
        let started = Date()
        let answer = DoctorProbe.launch(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script(grandchild)], within: 1)
        #expect(Date().timeIntervalSince(started) < 15)
        let text = try String(contentsOf: pidFile, encoding: .utf8)
        return try (answer, #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))))
    }

    /// Whether `pid` is gone within two seconds, which an orphan's reaping by launchd takes at most.
    private static func isGone(_ pid: pid_t) -> Bool {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if kill(pid, 0) != 0, errno == ESRCH {
                return true
            }
            usleep(20000)
        }
        return false
    }

    /// Stops a grandchild a launch left running, so a failing run leaves nothing behind either.
    private static func stray(_ pid: pid_t) {
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
    }

    @Test
    func aGrandchildThatIgnoresTerminationIsKilledWithTheChildsGroup() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let pidFile = directory.url.appendingPathComponent("grandchild.pid")

        let launched = try Self.launch({ "\($0); :" }, pidFile: pidFile)
        defer { Self.stray(launched.grandchild) }

        #expect(launched.answer == nil)
        #expect(Self.isGone(launched.grandchild))
    }

    @Test
    func aGrandchildLeftInTheBackgroundIsKilledThoughTheChildExited() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let pidFile = directory.url.appendingPathComponent("grandchild.pid")

        let launched = try Self.launch({ "\($0) & echo hi" }, pidFile: pidFile)
        defer { Self.stray(launched.grandchild) }

        #expect(launched.answer == nil)
        #expect(Self.isGone(launched.grandchild))
    }

    @Test
    func aProbeReleasedWithoutCloseRemovesItsScratchDirectory() throws {
        var probe: DoctorProbe? = try DoctorProbe(tool: GizmoHooks.tool, version: "1", environment: [:])
        let scratch = try #require(probe?.scratch)
        #expect(FileManager.default.fileExists(atPath: scratch.path))

        probe = nil

        #expect(!FileManager.default.fileExists(atPath: scratch.path))
    }
}
