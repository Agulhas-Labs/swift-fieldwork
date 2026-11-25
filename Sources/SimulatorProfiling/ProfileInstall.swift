// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SimulatorServices

/// Puts a measured profile where `ServiceProfiles.resolve(forRuntime:)` reads local ones.
public enum ProfileInstall {
    /// Writes the profile's JSON to `<local directory>/<runtime identifier>.json`, atomically, and returns the file.
    @discardableResult
    public static func install(_ profile: ServiceProfile, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        let directory = ServiceProfiles.localDirectory(environment: environment)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(profile.runtime.identifier).json")
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        try Data(ProfileSwiftSource.json(profile).utf8).write(to: temporary)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return url
    }
}
