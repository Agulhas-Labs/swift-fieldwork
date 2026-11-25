// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Fieldwork
import Foundation

/// The file a simulator's `launchd_sim` reads at start to switch services off.
public struct DisabledServicesOverride: Sendable {
    /// Where simulator devices keep their runtime data.
    public static let defaultRoot = URL(fileURLWithPath: "/private/var/tmp")

    private let root: URL

    public init(root: URL = defaultRoot) {
        self.root = root
    }

    /// The device's directory under the root; throws for a `udid` that is not a UUID, so no path is built from anything else.
    public func directory(for udid: String) throws -> URL {
        guard let uuid = UUID(uuidString: udid) else { throw SimulatorServicesError.invalidUDID(udid) }
        return root.appendingPathComponent("com.apple.CoreSimulator.SimDevice.\(uuid.uuidString)", isDirectory: true)
    }

    /// Switches exactly `labels` off for the device, as the labels this library owns there: a label an earlier write switched off and this one omits goes back to what it was before.
    /// Entries the library never touched are left as they are. The prior state of each label it takes over is recorded in a sidecar file, which `restore(for:)` reads.
    public func write(_ labels: [String], for udid: String) throws {
        let directory = try directory(for: udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var entries = try existingEntries(in: directory)
        var owned = try ownedEntries(in: directory)
        for label in owned.keys where !labels.contains(label) {
            put(back: owned[label], label: label, in: &entries)
            owned[label] = nil
        }
        for label in labels {
            if owned[label] == nil {
                owned[label] = entries[label] as? Bool ?? Self.absent
            }
            entries[label] = true
        }
        try save(entries, to: target(in: directory), in: directory)
        try save(owned, to: sidecar(in: directory), in: directory)
    }

    /// Puts every label this library switched off back to its state before the first write, and deletes the record of them; foreign entries and the directory stay.
    /// `launchd_sim` reads the file when the device boots, so a restore takes effect at the device's next boot.
    public func restore(for udid: String) throws {
        let directory = try directory(for: udid)
        let owned = try ownedEntries(in: directory)
        if !owned.isEmpty {
            var entries = try existingEntries(in: directory)
            for (label, prior) in owned {
                put(back: prior, label: label, in: &entries)
            }
            if entries.isEmpty {
                try removeIfPresent(target(in: directory))
            } else {
                try save(entries, to: target(in: directory), in: directory)
            }
        }
        try removeIfPresent(sidecar(in: directory))
    }

    /// The labels the device's file switches off; none where it has no file.
    public func labels(for udid: String) throws -> Set<String> {
        let entries = try existingEntries(in: directory(for: udid))
        return Set(entries.filter { $0.value as? Bool == true }.keys)
    }

    /// Deletes the device's directory; absent is fine.
    public func remove(for udid: String) throws {
        let directory = try directory(for: udid)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// The labels `launchctl print-disabled system` reports as disabled, in either of its formats (`disabled`/`enabled` or `true`/`false`).
    public static func disabledLabels(fromPrintDisabled output: String) -> Set<String> {
        var labels: Set<String> = []
        for line in output.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let label = parts[0].trimmingCharacters(in: .whitespaces)
            let state = parts[1].trimmingCharacters(in: .whitespaces)
            guard label.count > 2, label.hasPrefix("\""), label.hasSuffix("\""), state == "disabled" || state == "true" else { continue }
            labels.insert(String(label.dropFirst().dropLast()))
        }
        return labels
    }

    /// Asks the booted device which services it has switched off.
    public static func readBack(udid: String) throws -> Set<String> {
        guard UUID(uuidString: udid) != nil else { throw SimulatorServicesError.invalidUDID(udid) }
        let output = try Subprocess.run("/usr/bin/xcrun", ["simctl", "spawn", udid, "launchctl", "print-disabled", "system"], deadline: 30)
        guard output.succeeded else {
            throw SimulatorServicesError.commandFailed(command: "xcrun simctl spawn launchctl print-disabled system", standardError: output.standardError)
        }
        return disabledLabels(fromPrintDisabled: output.standardOutput)
    }

    private static let absent = "absent"

    private func put(back prior: Any?, label: String, in entries: inout [String: Any]) {
        if let bool = prior as? Bool {
            entries[label] = bool
        } else {
            entries[label] = nil
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func save(_ dictionary: [String: Any], to destination: URL, in directory: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
        let temporary = directory.appendingPathComponent(".disabled-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: temporary.path)
            guard rename(temporary.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func sidecar(in directory: URL) -> URL {
        directory.appendingPathComponent("fieldwork-disabled.plist")
    }

    private func ownedEntries(in directory: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: sidecar(in: directory)) else { return [:] }
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }

    private func target(in directory: URL) -> URL {
        directory.appendingPathComponent("disabled.plist")
    }

    private func existingEntries(in directory: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: target(in: directory)) else { return [:] }
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }
}
