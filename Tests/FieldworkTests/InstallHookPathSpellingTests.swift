// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers the spelling of an invoked path that an install registers: the one the shell used, with dots collapsed and nothing resolved.
struct InstallHookPathSpellingTests {
    /// A path that exists under `/private` keeps its `/private`, where URL standardizing rewrites `/private/var/…` to `/var/…`.
    @Test
    func aPrivatePrefixIsKept() throws {
        let scratch = try TemporaryDirectory()
        defer { scratch.remove() }
        let binary = scratch.url.appendingPathComponent("gizmo")
        try Data().write(to: binary)
        let spelled = "/private" + binary.path
        try #require(FileManager.default.fileExists(atPath: spelled))

        #expect(InvokedBinary.path(invokedAs: spelled, environment: [:], executable: nil) == spelled)
    }

    /// Dots and doubled slashes collapse without resolving anything.
    @Test
    func dotsCollapseWithoutResolving() {
        #expect(InvokedBinary.path(invokedAs: "/private/tmp/a/../b/./gizmo", environment: [:], executable: nil) == "/private/tmp/b/gizmo")
        #expect(InvokedBinary.path(invokedAs: "/tmp/a//b/gizmo", environment: [:], executable: nil) == "/tmp/a/b/gizmo")
    }
}
