// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers how a tool's children are started: without the terminal.
struct SubprocessInputTests {
    /// A spawned child reads the null device, never the terminal the tool asked its questions on.
    ///
    /// Handed that terminal, a child was stopped on touching it and ended at its deadline, where run by hand it took under a second.
    @Test
    func aSpawnedChildReadsTheNullDevice() {
        let process = Subprocess.process("/bin/sh", ["-c", "true"], in: nil, environment: nil)

        #expect((process.standardInput as? FileHandle) === FileHandle.nullDevice)
    }
}
