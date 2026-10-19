// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Darwin

/// A launch that could not start its child, or lost track of it: the call that failed and why.
struct LaunchFailure: Error, CustomStringConvertible {
    var executable: String
    var call: String
    var code: Int32

    var description: String {
        "\(call) failed for \(executable): \(String(cString: strerror(code))) (errno \(code))"
    }
}
