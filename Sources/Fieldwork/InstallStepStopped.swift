// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A step that stopped with an exit status instead of returning a report: a consumer turns its own exit error into this inside the step.
public struct InstallStepStopped: Error, Equatable, Sendable {
    public let status: Int32

    public init(status: Int32) {
        self.status = status
    }
}
