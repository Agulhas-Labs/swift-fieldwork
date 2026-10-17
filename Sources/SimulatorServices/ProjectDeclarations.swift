// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// What a project declares about the capabilities it uses.
public struct ProjectDeclarations: Sendable, Equatable {
    /// The keys of the entitlements file.
    public var entitlements: Set<String>
    /// The keys of the Info.plist.
    public var infoPlistKeys: Set<String>
    /// Whether the project carries a StoreKit configuration file.
    public var storeKitConfiguration: Bool

    /// The string values of the Info.plist's `UIBackgroundModes` array.
    public var backgroundModes: Set<String>

    public init(
        entitlements: Set<String> = [],
        infoPlistKeys: Set<String> = [],
        storeKitConfiguration: Bool = false,
        backgroundModes: Set<String> = []
    ) {
        self.entitlements = entitlements
        self.infoPlistKeys = infoPlistKeys
        self.storeKitConfiguration = storeKitConfiguration
        self.backgroundModes = backgroundModes
    }

    /// The top-level keys of an XML or binary property list whose value is not boolean `false`.
    public static func keys(ofPlist data: Data) throws -> Set<String> {
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        return Set(dictionary.filter { ($0.value as? Bool) != false }.keys)
    }

    /// Reads the declarations from the files given; a nil file contributes nothing.
    public static func read(entitlements: URL?, infoPlist: URL?, storeKitConfiguration: Bool) throws -> ProjectDeclarations {
        let entitlementKeys = try entitlements.map { try keys(ofPlist: Data(contentsOf: $0)) } ?? []
        var plistKeys: Set<String> = []
        var modes: Set<String> = []
        if let infoPlist {
            let data = try Data(contentsOf: infoPlist)
            plistKeys = try keys(ofPlist: data)
            if let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                modes = Set((dictionary["UIBackgroundModes"] as? [Any] ?? []).compactMap { $0 as? String })
            }
        }
        return ProjectDeclarations(entitlements: entitlementKeys, infoPlistKeys: plistKeys, storeKitConfiguration: storeKitConfiguration, backgroundModes: modes)
    }

    /// The capabilities the declarations call for.
    public var capabilities: Set<Capability> {
        var found: Set<Capability> = []
        for rule in Self.rules where rule.matches(self) {
            found.insert(rule.capability)
        }
        if storeKitConfiguration {
            found.insert(.storeKit)
        }
        return found
    }

    /// Every declaration no rule accounts for, sorted: entitlements, `NS…UsageDescription` keys and `UIBackgroundModes:<value>`. A caller that keeps services on for what a project declares should not switch any off while this is non-empty, because what these keys need is unknown.
    public var unmapped: [String] {
        var found: [String] = []
        found += entitlements.filter { key in
            !Self.rules.contains { $0.entitlements.contains(key) } && !Self.inertEntitlements.contains(key)
        }
        found += infoPlistKeys.filter { key in
            key.hasPrefix("NS") && key.hasSuffix("UsageDescription") && !Self.rules.contains { $0.infoPlistKeys.contains(key) }
        }
        found += backgroundModes.filter { mode in
            !Self.rules.contains { $0.backgroundModes.contains(mode) } && !Self.inertBackgroundModes.contains(mode)
        }.map { "UIBackgroundModes:\($0)" }
        return found.sorted()
    }

    /// Keys that need no service a profile may switch off: they are served by services that are never switched off, or by none.
    private static let inertEntitlements: Set<String> = [
        "application-identifier",
        "com.apple.developer.team-identifier",
        "get-task-allow",
        "keychain-access-groups",
        "com.apple.security.application-groups",
        "com.apple.developer.default-data-protection",
    ]

    private static let inertBackgroundModes: Set<String> = ["fetch", "processing"]

    private struct Rule {
        let capability: Capability
        let entitlements: Set<String>
        let infoPlistKeys: Set<String>
        let backgroundModes: Set<String>

        init(_ capability: Capability, _ entitlements: Set<String>, _ infoPlistKeys: Set<String>, _ backgroundModes: Set<String> = []) {
            self.capability = capability
            self.entitlements = entitlements
            self.infoPlistKeys = infoPlistKeys
            self.backgroundModes = backgroundModes
        }

        func matches(_ declarations: ProjectDeclarations) -> Bool {
            !declarations.entitlements.isDisjoint(with: entitlements)
                || !declarations.infoPlistKeys.isDisjoint(with: infoPlistKeys)
                || !declarations.backgroundModes.isDisjoint(with: backgroundModes)
        }
    }

    private static let rules: [Rule] = [
        Rule(
            .healthKit,
            ["com.apple.developer.healthkit", "com.apple.developer.healthkit.access", "com.apple.developer.healthkit.background-delivery"],
            ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"]
        ),
        Rule(.pushNotifications, ["aps-environment"], [], ["remote-notification"]),
        Rule(
            .iCloud,
            [
                "com.apple.developer.icloud-services",
                "com.apple.developer.icloud-container-identifiers",
                "com.apple.developer.icloud-container-environment",
                "com.apple.developer.ubiquity-kvstore-identifier",
            ],
            []
        ),
        Rule(.associatedDomains, ["com.apple.developer.associated-domains"], []),
        Rule(.contacts, [], ["NSContactsUsageDescription"]),
        Rule(.calendars, [], ["NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription"]),
        Rule(.photos, [], ["NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"]),
        Rule(.reminders, [], ["NSRemindersUsageDescription", "NSRemindersFullAccessUsageDescription"]),
    ]
}
