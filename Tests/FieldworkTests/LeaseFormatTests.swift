// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The lease file is read by every tool built on any version of this package, so its bytes are a contract: a fixture written by the first release's encoder must come back out of this one unchanged.
struct LeaseFormatTests {
    private let udid = "FIXTURE-DEVICE"

    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "lease-0.1.2", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    /// A fixed lease, at whole seconds, with every field set.
    private let created = Date(timeIntervalSince1970: 1_800_000_000)

    /// The fixture decodes, and encodes back to the same bytes: key order, date format and omitted optionals included.
    @Test
    func theFixtureRoundTripsByteForByte() throws {
        let bytes = try fixture()
        let lease = try LeaseStore.decoder.decode(DeviceLease.self, from: bytes)
        #expect(lease == DeviceLease(token: "fixture-token", holderPID: 4242, createdAt: created, expiresAt: created.addingTimeInterval(3600), createdDevice: true, clonedFrom: nil, physicalDevice: true))
        #expect(try LeaseStore.encoder.encode(lease) == bytes)
    }

    /// The store writes the lease to `<udid>.json` in its directory, with the fixture's bytes.
    @Test
    func theStoreWritesTheFixtureBytesToTheUDIDsFile() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let store = LeaseStore(directory: directory.url, isAlive: { _ in true })
        _ = try store.acquire(udid: udid, ttl: 3600, holderPID: 4242, now: created, createdDevice: true, clonedFrom: nil, physicalDevice: true, token: "fixture-token")
        let file = directory.url.appendingPathComponent("FIXTURE-DEVICE.json")
        #expect(try Data(contentsOf: file) == fixture())
    }
}
