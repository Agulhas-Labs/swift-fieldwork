// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A scratch directory of the test's own, under the system's temporary directory: `let directory = try TemporaryDirectory()` then `defer { directory.remove() }`.
///
/// The `defer` is the cleanup, and it also keeps the value alive to the end of the test. `deinit` removes it too, for a test that throws before its `defer` is in place.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simulator-services-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Removes the directory and everything in it.
    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        remove()
    }
}
