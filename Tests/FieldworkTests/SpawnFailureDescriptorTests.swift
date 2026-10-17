// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// A spawn that times out while a grandchild still holds its pipes open has closed both read ends by the time the call returns.
///
/// The count is taken in a child process that runs nothing else, because the test runner's other suites open and close descriptors of their own beside this one.
struct SpawnFailureDescriptorTests {
    /// Clearing a handle's readability handler does not reliably release it, so read ends left to close on release outlived the call, a few in every fifty calls and closed moments later; the count is taken after every call and allows none, since a count taken only after the last call missed all but the leaks still open at that instant. One spawn runs before the count so that whatever the first spawn sets up for good is not read as a leak.
    @Test
    func fiftyTimedOutSpawnsLeaveTheOpenDescriptorCountWhereItWas() async {
        await #expect(processExitsWith: .success) {
            _ = try? Subprocess.run("/bin/sh", ["-c", "sleep 3 & sleep 3"], deadline: 0.1)
            let before = SpawnFailureDescriptorTests.openDescriptors()
            for _ in 0 ..< 50 {
                let output = try? Subprocess.run("/bin/sh", ["-c", "sleep 3 & sleep 3"], deadline: 0.1)
                #expect(output?.standardError.contains("timed out") == true)
                let after = SpawnFailureDescriptorTests.openDescriptors()
                #expect(after <= before, "open descriptors went from \(before) to \(after)")
            }
        }
    }

    /// The number of descriptors this process has open, read from `/dev/fd`.
    static func openDescriptors() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }
}
