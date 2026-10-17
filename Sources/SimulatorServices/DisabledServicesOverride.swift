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

    /// Switches `labels` off for the device, keeping any entries the file already has.
    public func write(_ labels: [String], for udid: String) throws {
        let directory = try directory(for: udid)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var entries = try existingEntries(in: directory)
        for label in labels {
            entries[label] = true
        }
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
        let temporary = directory.appendingPathComponent(".disabled-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: temporary.path)
            guard rename(temporary.path, target(in: directory).path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
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

    private func target(in directory: URL) -> URL {
        directory.appendingPathComponent("disabled.plist")
    }

    private func existingEntries(in directory: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: target(in: directory)) else { return [:] }
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }
}
