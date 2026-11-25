// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation

/// What was decided about one service of a runtime.
public enum Disposition: String, Codable, Sendable {
    /// Safe to switch off.
    case disable
    /// The runtime needs it.
    case core
    /// Too cheap to be worth switching off.
    case belowThreshold
    /// Never ran at boot.
    case notRunning
    /// A service every app needs to install, launch and run, so it is never a candidate for switching off.
    case infrastructure
    /// Switching it off broke the health check.
    case keptByHealth
    /// A candidate the health check never had off, because the input app's capability kept it on; it stays on until a run that has it off passes.
    case unchecked
}

/// A service measured on a runtime.
public struct ServiceEntry: Codable, Sendable, Equatable {
    public let label: String
    public let domain: Domain
    public let start: Start
    public let ranAtBoot: Bool
    public let peakFootprintMB: Double?
    public let cpuSeconds: Double?
    public let disposition: Disposition

    public init(label: String, domain: Domain, start: Start, ranAtBoot: Bool, peakFootprintMB: Double?, cpuSeconds: Double?, disposition: Disposition) {
        self.label = label
        self.domain = domain
        self.start = start
        self.ranAtBoot = ranAtBoot
        self.peakFootprintMB = peakFootprintMB
        self.cpuSeconds = cpuSeconds
        self.disposition = disposition
    }
}

/// The runtime a profile was measured on.
public struct ProfileRuntime: Codable, Sendable, Equatable {
    public let identifier: String
    public let version: String
    public let build: String

    public init(identifier: String, version: String, build: String) {
        self.identifier = identifier
        self.version = version
        self.build = build
    }
}

/// How a profile was measured.
public struct ProfileMethod: Codable, Sendable, Equatable {
    public let costWindowSeconds: Int
    public let footprintThresholdMB: Double
    public let cpuThresholdSeconds: Double
    public let checks: [String]
    /// The capabilities, by name, whose services stayed on during the health stage, so their being off was not checked.
    public let keptForInput: [String]

    public init(costWindowSeconds: Int, footprintThresholdMB: Double, cpuThresholdSeconds: Double, checks: [String], keptForInput: [String] = []) {
        self.costWindowSeconds = costWindowSeconds
        self.footprintThresholdMB = footprintThresholdMB
        self.cpuThresholdSeconds = cpuThresholdSeconds
        self.checks = checks
        self.keptForInput = keptForInput
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        costWindowSeconds = try container.decode(Int.self, forKey: .costWindowSeconds)
        footprintThresholdMB = try container.decode(Double.self, forKey: .footprintThresholdMB)
        cpuThresholdSeconds = try container.decode(Double.self, forKey: .cpuThresholdSeconds)
        checks = try container.decode([String].self, forKey: .checks)
        keptForInput = try container.decodeIfPresent([String].self, forKey: .keptForInput) ?? []
    }
}

/// What a plan switches off, and what it keeps for the capabilities asked for.
public struct SlimPlan: Sendable, Equatable {
    /// The labels to switch off.
    public let disabled: [String]
    /// For each kept capability, the labels it spared from being switched off.
    public let kept: [Capability: [String]]
}

/// The versioned, measured list of services one runtime can run without.
public struct ServiceProfile: Codable, Sendable, Equatable {
    /// The newest format this library reads.
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let profileVersion: Int
    public let runtime: ProfileRuntime
    public let deviceType: String
    public let generated: String
    public let method: ProfileMethod
    public let services: [ServiceEntry]
    /// For each capability, the labels that serve it on this runtime.
    public let capabilities: [Capability: [String]]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        profileVersion: Int,
        runtime: ProfileRuntime,
        deviceType: String,
        generated: String,
        method: ProfileMethod,
        services: [ServiceEntry],
        capabilities: [Capability: [String]]
    ) {
        self.schemaVersion = schemaVersion
        self.profileVersion = profileVersion
        self.runtime = runtime
        self.deviceType = deviceType
        self.generated = generated
        self.method = method
        self.services = services
        self.capabilities = capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version <= Self.currentSchemaVersion else {
            throw SimulatorServicesError.unsupportedSchema(found: version, supported: Self.currentSchemaVersion)
        }
        schemaVersion = version
        profileVersion = try container.decode(Int.self, forKey: .profileVersion)
        runtime = try container.decode(ProfileRuntime.self, forKey: .runtime)
        deviceType = try container.decode(String.self, forKey: .deviceType)
        generated = try container.decode(String.self, forKey: .generated)
        method = try container.decode(ProfileMethod.self, forKey: .method)
        services = try container.decode([ServiceEntry].self, forKey: .services)
        let raw = try container.decode([String: [String]].self, forKey: .capabilities)
        capabilities = Dictionary(uniqueKeysWithValues: raw.compactMap { key, labels in Capability(rawValue: key).map { ($0, labels) } })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(profileVersion, forKey: .profileVersion)
        try container.encode(runtime, forKey: .runtime)
        try container.encode(deviceType, forKey: .deviceType)
        try container.encode(generated, forKey: .generated)
        try container.encode(method, forKey: .method)
        try container.encode(services, forKey: .services)
        try container.encode(Dictionary(uniqueKeysWithValues: capabilities.map { ($0.key.rawValue, $0.value) }), forKey: .capabilities)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, profileVersion, runtime, deviceType, generated, method, services, capabilities
    }

    /// The labels to switch off, sorted.
    public var disabledLabels: [String] {
        services.filter { $0.disposition == .disable }.map(\.label).sorted()
    }

    /// The labels serving `capability` on this runtime, sorted.
    public func labels(for capability: Capability) -> [String] {
        (capabilities[capability] ?? []).sorted()
    }

    /// The labels to switch off while keeping what `keeping` needs.
    public func plan(keeping: Set<Capability>) -> SlimPlan {
        let disabled = Set(disabledLabels)
        var kept: [Capability: [String]] = [:]
        var spared: Set<String> = []
        for capability in keeping {
            let own = labels(for: capability).filter { disabled.contains($0) }
            if !own.isEmpty {
                kept[capability] = own
                spared.formUnion(own)
            }
        }
        return SlimPlan(disabled: disabled.subtracting(spared).sorted(), kept: kept)
    }
}

/// Where a resolved profile came from.
public enum ProfileSource: Sendable, Equatable {
    /// Shipped in the library.
    case bundled
    /// Measured on this machine: the file it was read from.
    case local(URL)
}

/// The answer to looking a runtime's profile up.
public enum ProfileResolution: Sendable {
    /// A profile, and where it came from.
    case found(ServiceProfile, ProfileSource)
    /// No bundled profile and no local file.
    case none
    /// A local file that was refused, and why; a refused file is never used.
    case unreadable(URL, String)

    /// The profile found, or nil.
    public var profile: ServiceProfile? {
        if case let .found(profile, _) = self {
            return profile
        }
        return nil
    }
}

/// The profiles that ship with the library.
public enum ServiceProfiles {
    /// The profile for a runtime: the bundled one, else one measured on this machine, or nil, in which case boot stock.
    public static func profile(forRuntime identifier: String) -> ServiceProfile? {
        resolve(forRuntime: identifier).profile
    }

    /// The profile for a runtime and where it came from. A bundled profile (reviewed) wins over a local file. A local file that does not decode, is in a newer format, or is for another runtime is refused and reported, never used.
    public static func resolve(forRuntime identifier: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> ProfileResolution {
        if let text = bundled[identifier], let profile = try? JSONDecoder().decode(ServiceProfile.self, from: Data(text.utf8)) {
            return .found(profile, .bundled)
        }
        let url = localDirectory(environment: environment).appendingPathComponent("\(identifier).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .none }
        do {
            let profile = try JSONDecoder().decode(ServiceProfile.self, from: Data(contentsOf: url))
            guard profile.runtime.identifier == identifier else {
                return .unreadable(url, "its runtime is \(profile.runtime.identifier), not \(identifier)")
            }
            return .found(profile, .local(url))
        } catch {
            return .unreadable(url, "\(error)")
        }
    }

    /// The directory of locally measured profiles: `FIELDWORK_SERVICE_PROFILES` when it holds an absolute path, else `~/.config/fieldwork/service-profiles`. A profile is the file `<runtime identifier>.json` in it.
    public static func localDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let value = environment["FIELDWORK_SERVICE_PROFILES"], value.hasPrefix("/") {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return AgentPaths.userHome(environment: environment).appendingPathComponent(".config/fieldwork/service-profiles", isDirectory: true)
    }

    /// Runtime identifier to profile JSON text, merged from `sources`.
    static let bundled: [String: String] = sources.reduce(into: [:]) { $0.merge($1) { _, new in new } }

    /// A profile file `iOS27Point0.swift` adds `static let iOS27Point0: [String: String] = [...]` in an extension, and registers it by adding its name to this list: the one edit to this file.
    private static let sources: [[String: String]] = [
        iOS27Point0,
    ]
}
