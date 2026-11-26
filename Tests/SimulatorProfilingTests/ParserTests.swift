// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the parser of the launchctl output the sampler reads, on output captured from the real command.
struct ParserTests {
    @Test func `launchctl list keeps the running jobs and leaves out the dash rows`() throws {
        let text = try String(contentsOf: fixture("launchctl-list.txt"), encoding: .utf8)

        let labels = LaunchctlList.runningLabels(parsing: text)

        #expect(labels.count == 10)
        #expect(labels[87302] == "com.apple.homed")
        #expect(labels[87501] == "com.apple.devicecheckd")
        #expect(!labels.values.contains("com.apple.progressd"))
    }
}
