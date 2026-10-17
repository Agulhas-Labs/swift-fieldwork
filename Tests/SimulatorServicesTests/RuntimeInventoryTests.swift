// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorServices
import Testing

/// What a runtime ships is read from its property lists: each job's start kind, program and domain, and the files that could not be read.
struct RuntimeInventoryTests {
    private func inventory() throws -> RuntimeInventory {
        try RuntimeInventory.read(runtimeRoot: fixture("RuntimeRoot"))
    }

    @Test
    func jobsAreClassifiedAndSortedByLabel() throws {
        let jobs = try inventory().jobs
        #expect(jobs.map(\.label) == [
            "com.example.agentd", "com.example.demandd", "com.example.dictd", "com.example.gizmod", "com.example.loadd", "com.example.otherd",
        ])
        #expect(jobs.map(\.start) == [.atLoad, .onDemand, .keepAlive, .keepAlive, .atLoad, .other])
    }

    @Test
    func keepAliveFalseFallsThroughToRunAtLoad() throws {
        let job = try #require(inventory().jobs.first { $0.label == "com.example.loadd" })
        #expect(job.start == .atLoad)
        #expect(job.program == nil)
    }

    @Test
    func programComesFromProgramThenFirstArgument() throws {
        let jobs = try inventory().jobs
        #expect(jobs.first { $0.label == "com.example.gizmod" }?.program == "/usr/libexec/gizmod")
        #expect(jobs.first { $0.label == "com.example.dictd" }?.program == "/usr/libexec/dictd")
    }

    @Test
    func domainFollowsTheDirectory() throws {
        let jobs = try inventory().jobs
        #expect(jobs.first { $0.label == "com.example.agentd" }?.domain == .agent)
        #expect(jobs.first { $0.label == "com.example.gizmod" }?.domain == .daemon)
    }

    @Test
    func filesWithoutALabelOrThatDoNotParseAreUnreadable() throws {
        #expect(try inventory().unreadable == ["broken.plist", "nolabel.plist"])
    }

    @Test
    func aMissingDirectoryIsEmptyNotAnError() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let inventory = try RuntimeInventory.read(runtimeRoot: directory.url)
        #expect(inventory.jobs.isEmpty)
        #expect(inventory.unreadable.isEmpty)
    }
}
