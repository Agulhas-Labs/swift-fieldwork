// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation
import SimulatorServices

/// Why a `simctl` call on a profiling device failed.
public struct ProfileDeviceError: Error, CustomStringConvertible, Equatable {
    public let command: String
    public let detail: String

    public var description: String {
        "\(command) failed: \(detail)"
    }
}

/// Every device this process created and has not yet deleted, so that every way out of the process can delete them.
public final class DeviceRegistry: @unchecked Sendable {
    /// The registry the executable and its signal handlers share.
    public static let shared = DeviceRegistry()

    private let lock = NSLock()
    private let deletion = NSLock()
    private var recorded: [String] = []
    private let remove: @Sendable (String) -> Bool

    /// Makes a registry whose devices are deleted by `remove`, which answers whether the device is gone; by default the device is shut down and deleted with `simctl`.
    public init(remove: @escaping @Sendable (String) -> Bool = { ProfileDevice.removeFromSystem(udid: $0) }) {
        self.remove = remove
    }

    /// The devices recorded and not yet deleted.
    public var udids: [String] {
        lock.withLock { recorded }
    }

    /// Records a device.
    public func record(_ udid: String) {
        lock.withLock { recorded.append(udid) }
    }

    /// Forgets a device.
    public func unregister(_ udid: String) {
        lock.withLock { recorded.removeAll { $0 == udid } }
    }

    /// Deletes a recorded device and answers whether it is gone; a device already deleted, here or by another caller, counts as gone.
    ///
    /// Deletions run one at a time, so a caller never returns while a deletion started elsewhere is still running.
    public func delete(_ udid: String) -> Bool {
        deletion.withLock {
            guard udids.contains(udid) else { return true }
            guard remove(udid) else { return false }
            unregister(udid)
            return true
        }
    }

    /// Deletes every recorded device and answers the ones that could not be deleted.
    @discardableResult
    public func deleteAll() -> [String] {
        udids.filter { !delete($0) }
    }
}

/// A simulator this process created to measure on.
public struct ProfileDevice: Sendable {
    public let udid: String
    private let registry: DeviceRegistry

    /// Creates a device of `deviceType` on `runtime`, and records it before returning.
    public static func create(deviceType: String, runtime: String, registry: DeviceRegistry = .shared) throws -> ProfileDevice {
        let name = "fieldwork-profile-" + UUID().uuidString.prefix(8).lowercased()
        let output = try Subprocess.run("/usr/bin/xcrun", ["simctl", "create", name, deviceType, runtime], deadline: 60)
        let udid = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard output.succeeded, !udid.isEmpty else {
            throw ProfileDeviceError(command: "simctl create", detail: output.standardError)
        }
        registry.record(udid)
        return ProfileDevice(udid: udid, registry: registry)
    }

    /// Starts the boot and returns at once.
    public func boot() throws {
        try run(["boot", udid], deadline: 60)
    }

    /// Waits for the boot to finish, up to `deadline` seconds (five minutes by default).
    public func waitUntilBooted(deadline: TimeInterval = 300) throws {
        try run(["bootstatus", udid, "-b"], deadline: deadline)
    }

    /// Shuts the device down.
    public func shutdown() throws {
        try run(["shutdown", udid], deadline: 60)
    }

    /// Erases the device's content.
    public func erase() throws {
        try run(["erase", udid], deadline: 60)
    }

    /// Runs a command inside the device.
    public func spawn(_ arguments: [String], deadline: TimeInterval) throws -> Subprocess.Output {
        try Subprocess.run("/usr/bin/xcrun", ["simctl", "spawn", udid] + arguments, deadline: deadline)
    }

    /// Shuts the device down (a failure is ignored), deletes it, removes its disabled-services directory and forgets it.
    public func delete() throws {
        guard registry.delete(udid) else {
            throw ProfileDeviceError(command: "simctl delete", detail: "the device \(udid) could not be deleted")
        }
        registry.unregister(udid)
    }

    /// Shuts the device down, deletes it with `simctl` and removes its disabled-services directory; true where `simctl` deleted it.
    public static func removeFromSystem(udid: String) -> Bool {
        _ = try? Subprocess.run("/usr/bin/xcrun", ["simctl", "shutdown", udid], deadline: 60)
        let deleted = (try? Subprocess.run("/usr/bin/xcrun", ["simctl", "delete", udid], deadline: 60))?.succeeded ?? false
        try? DisabledServicesOverride().remove(for: udid)
        return deleted
    }

    private func run(_ arguments: [String], deadline: TimeInterval) throws {
        let output = try Subprocess.run("/usr/bin/xcrun", ["simctl"] + arguments, deadline: deadline)
        guard output.succeeded else {
            throw ProfileDeviceError(command: "simctl \(arguments[0])", detail: output.standardError)
        }
    }
}
