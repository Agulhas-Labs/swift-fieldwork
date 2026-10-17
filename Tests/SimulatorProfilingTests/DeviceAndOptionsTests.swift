// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorProfiling
import Testing

/// Covers the registry every way out deletes from, the command line, and the booted-device listing.
struct DeviceAndOptionsTests {
    /// The devices a registry asked to delete, in order.
    private final class Removals: @unchecked Sendable {
        private let lock = NSLock()
        private var udids: [String] = []
        let failing: Set<String>

        init(failing: Set<String> = []) {
            self.failing = failing
        }

        var removed: [String] {
            lock.withLock { udids }
        }

        func remove(_ udid: String) -> Bool {
            lock.withLock { udids.append(udid) }
            return !failing.contains(udid)
        }
    }

    @Test func `deleting all removes every recorded device and forgets it`() {
        let removals = Removals()
        let registry = DeviceRegistry(remove: { removals.remove($0) })
        registry.record("one")
        registry.record("two")

        let left = registry.deleteAll()

        #expect(left.isEmpty)
        #expect(removals.removed == ["one", "two"])
        #expect(registry.udids.isEmpty)
    }

    @Test func `a device that cannot be deleted stays recorded and is reported`() {
        let removals = Removals(failing: ["stuck"])
        let registry = DeviceRegistry(remove: { removals.remove($0) })
        registry.record("stuck")
        registry.record("fine")

        #expect(registry.deleteAll() == ["stuck"])
        #expect(registry.udids == ["stuck"])
    }

    @Test func `a device already deleted is not deleted twice`() {
        let removals = Removals()
        let registry = DeviceRegistry(remove: { removals.remove($0) })
        registry.record("one")

        #expect(registry.delete("one"))
        #expect(registry.delete("one"))
        #expect(removals.removed == ["one"])
    }

    @Test func `recording from many threads loses none`() {
        let registry = DeviceRegistry(remove: { _ in true })

        DispatchQueue.concurrentPerform(iterations: 200) { registry.record("device-\($0)") }

        #expect(registry.udids.count == 200)
    }

    @Test func `the options take their defaults and every flag`() throws {
        let defaults = try ProfileOptions.parse(["--runtime", "r", "--device-type", "d", "--out", "p.json"])
        #expect(defaults == ProfileOptions(runtime: "r", deviceType: "d", output: "p.json"))
        #expect(defaults.window == 300)
        #expect(defaults.footprintThresholdMB == 4)
        #expect(defaults.cpuThresholdSeconds == 0.5)
        #expect(defaults.profileVersion == 1)
        #expect(!defaults.allowBooted)

        let all = try ProfileOptions.parse([
            "--runtime", "r", "--device-type", "d", "--out", "p.json", "--window", "60", "--footprint-threshold", "8",
            "--cpu-threshold", "1.5", "--profile-version", "3", "--allow-booted",
        ])
        #expect(all.window == 60)
        #expect(all.footprintThresholdMB == 8)
        #expect(all.cpuThresholdSeconds == 1.5)
        #expect(all.profileVersion == 3)
        #expect(all.allowBooted)
    }

    @Test func `a command line that cannot be used is refused with a reason`() {
        let base = ["--runtime", "r", "--device-type", "d", "--out", "p.json"]

        #expect(throws: ProfileUsageError(message: "unknown argument --bogus")) { try ProfileOptions.parse(base + ["--bogus"]) }
        #expect(throws: ProfileUsageError(message: "--out is required")) { try ProfileOptions.parse(["--runtime", "r", "--device-type", "d"]) }
        #expect(throws: ProfileUsageError(message: "--window needs a value")) { try ProfileOptions.parse(base + ["--window"]) }
        #expect(throws: ProfileUsageError(message: "--window needs a number of at least 1, not 0")) { try ProfileOptions.parse(base + ["--window", "0"]) }
        #expect(throws: ProfileUsageError(message: "--cpu-threshold needs a number of at least 0.0, not x")) { try ProfileOptions.parse(base + ["--cpu-threshold", "x"]) }
    }

    @Test func `the booted listing names each device with its identifier`() throws {
        let udid = UUID().uuidString
        let json = """
        {"devices": {"com.example.runtime": [{"name": "iPhone 17", "udid": "__UDID__", "state": "Booted"}], "com.example.empty": []}}
        """.replacingOccurrences(of: "__UDID__", with: udid)

        let booted = try ProfileCommand.booted(fromListing: Data(json.utf8))

        #expect(booted == ["iPhone 17 (__UDID__)".replacingOccurrences(of: "__UDID__", with: udid)])
        #expect(try ProfileCommand.booted(fromListing: Data(#"{"devices": {"r": []}}"#.utf8)).isEmpty)
    }
}
