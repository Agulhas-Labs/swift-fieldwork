// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorServices
import Testing

/// A device's memory is its own `launchd_sim` tree's count and summed footprint, and nothing when it is not booted.
struct DeviceMemoryTests {
    private let udid = UUID().uuidString
    private let other = UUID().uuidString

    private var table: String {
        """
        1 0 0:01.00 /sbin/launchd
        10 1 0:01.00 launchd_sim /Devices/\(udid)/data/launchd_bootstrap.plist
        11 10 0:00.50 /RT/usr/libexec/a
        12 11 0:00.25 /RT/usr/libexec/b
        20 1 0:01.00 launchd_sim /Devices/\(other)/data/launchd_bootstrap.plist
        21 20 0:00.50 /RT/usr/libexec/c
        """
    }

    private let report = """
    a [10]: 64-bit    Footprint: 10 MB (16384 bytes per page)
    b [11]: 64-bit    Footprint: 20 MB (16384 bytes per page)
    c [12]: 64-bit    Footprint: 1 GB (16384 bytes per page)
    """

    @Test func `a table with two devices counts only the named one's tree and sums only its pids`() throws {
        let memory = try #require(DeviceMemory(udid: udid, processTable: table) { _ in report })

        #expect(memory == DeviceMemory(udid: udid, processTable: table) { _ in report })
        #expect(memory.processes == 3)
        #expect(memory.footprintMB == 1054)
    }

    @Test func `a device with no launchd_sim gives nil and reads no footprint`() {
        var asked = false
        let memory = DeviceMemory(udid: UUID().uuidString, processTable: table) { _ in
            asked = true
            return ""
        }

        #expect(memory == nil)
        #expect(!asked)
    }

    @Test func `the footprint closure receives exactly the tree's pids`() {
        var received: [Int32] = []
        _ = DeviceMemory(udid: other, processTable: table) { pids in
            received = pids
            return ""
        }

        #expect(received == [20, 21])
    }

    @Test func `an error from the footprint closure reaches the caller`() {
        struct Failure: Error {}

        #expect(throws: Failure.self) {
            _ = try DeviceMemory(udid: udid, processTable: table) { _ in throw Failure() }
        }
    }
}
