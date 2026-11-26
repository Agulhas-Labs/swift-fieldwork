// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorServices
import Testing

/// Covers the parsers of `ps` and `footprint`, on output captured from the real commands.
struct ProcessTableTests {
    private func psFixture(udid: String, other: String) throws -> String {
        try String(contentsOf: fixture("ps.txt"), encoding: .utf8)
            .replacingOccurrences(of: "__UDID__", with: udid)
            .replacingOccurrences(of: "__OTHER__", with: other)
    }

    @Test func `the process table reads every row of the captured ps output`() throws {
        let table = try ProcessTable(parsing: psFixture(udid: UUID().uuidString, other: UUID().uuidString))

        #expect(table.rows.count == 12)
        #expect(table.rows[0] == ProcessRow(pid: 1, parent: 0, cpuSeconds: 45 * 60 + 24.67, command: "/sbin/launchd"))
        #expect(table.rows[3].command == "/RT/usr/libexec/UserEventAgent (System)")
    }

    @Test func `the tree is the launchd_sim of the device and everything below it`() throws {
        let udid = UUID().uuidString
        let table = try ProcessTable(parsing: psFixture(udid: udid, other: UUID().uuidString))

        #expect(table.tree(underLaunchdSimFor: udid) == [87182, 87184, 87185, 87186, 87187, 87223, 87301, 87364, 87501])
    }

    @Test func `the tree of another device does not include this one`() throws {
        let other = UUID().uuidString
        let table = try ProcessTable(parsing: psFixture(udid: UUID().uuidString, other: other))

        #expect(table.tree(underLaunchdSimFor: other) == [901])
        #expect(table.tree(underLaunchdSimFor: UUID().uuidString).isEmpty)
    }

    @Test func `the tree follows grandchildren`() {
        let udid = UUID().uuidString
        let table = ProcessTable(parsing: """
        10 1 0:01.00 launchd_sim /Devices/\(udid)/data/launchd_bootstrap.plist
        11 10 0:00.50 /RT/usr/libexec/parent
        12 11 0:00.25 /RT/usr/libexec/child
        13 1 0:00.25 /usr/libexec/unrelated
        """)

        #expect(table.tree(underLaunchdSimFor: udid) == [10, 11, 12])
    }

    @Test func `a ps time column in each of its shapes is read as seconds`() {
        #expect(ProcessTable.cpuSeconds(fromTime: "0:00.50") == 0.5)
        #expect(ProcessTable.cpuSeconds(fromTime: "12:34") == 754)
        #expect(ProcessTable.cpuSeconds(fromTime: "1:02:03") == 3723)
        #expect(ProcessTable.cpuSeconds(fromTime: "1:02:03.50") == 3723.5)
        #expect(ProcessTable.cpuSeconds(fromTime: "2-01:00:00") == 176_400)
        #expect(ProcessTable.cpuSeconds(fromTime: "garbage") == nil)
        #expect(ProcessTable.cpuSeconds(fromTime: "5") == nil)
    }

    @Test func `the footprint report reads the heading of each process`() throws {
        let text = try String(contentsOf: fixture("footprint.txt"), encoding: .utf8)

        let megabytes = FootprintReport.megabytes(parsing: text)

        #expect(megabytes == [89242: 410, 89376: 1936.0 / 1024])
    }

    @Test func `the footprint report converts bytes and gigabytes`() {
        let megabytes = FootprintReport.megabytes(parsing: """
        a [5]: 64-bit    Footprint: 2097152 B (16384 bytes per page)
        b [6]: 64-bit    Footprint: 1.5 GB (16384 bytes per page)
        Summary Footprint: 1.5 GB
        """)

        #expect(megabytes == [5: 2, 6: 1536])
    }
}
