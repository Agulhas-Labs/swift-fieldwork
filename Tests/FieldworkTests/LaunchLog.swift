// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

final class LaunchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Call] = []

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func record(binary: String, arguments: [String], environment: [String: String], limit: TimeInterval) {
        lock.withLock { recorded.append(Call(binary: binary, arguments: arguments, environment: environment, limit: limit)) }
    }
}

extension LaunchLog {
    struct Call {
        let binary: String
        let arguments: [String]
        let environment: [String: String]
        let limit: TimeInterval
    }
}
