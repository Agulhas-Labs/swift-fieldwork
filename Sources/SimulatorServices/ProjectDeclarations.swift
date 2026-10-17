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

    public init(entitlements: Set<String> = [], infoPlistKeys: Set<String> = [], storeKitConfiguration: Bool = false) {
        self.entitlements = entitlements
        self.infoPlistKeys = infoPlistKeys
        self.storeKitConfiguration = storeKitConfiguration
    }

    /// The top-level keys of an XML or binary property list whose value is not boolean `false`.
    public static func keys(ofPlist data: Data) throws -> Set<String> {
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [] }
        return Set(dictionary.filter { ($0.value as? Bool) != false }.keys)
    }

    /// Reads the declarations from the files given; a nil file contributes nothing.
    public static func read(entitlements: URL?, infoPlist: URL?, storeKitConfiguration: Bool) throws -> ProjectDeclarations {
        let entitlementKeys = try entitlements.map { try keys(ofPlist: Data(contentsOf: $0)) } ?? []
        let plistKeys = try infoPlist.map { try keys(ofPlist: Data(contentsOf: $0)) } ?? []
        return ProjectDeclarations(entitlements: entitlementKeys, infoPlistKeys: plistKeys, storeKitConfiguration: storeKitConfiguration)
    }

    /// The capabilities the declarations call for.
    public var capabilities: Set<Capability> {
        var found: Set<Capability> = []
        for rule in Self.rules where !entitlements.isDisjoint(with: rule.entitlements) || !infoPlistKeys.isDisjoint(with: rule.infoPlistKeys) {
            found.insert(rule.capability)
        }
        if storeKitConfiguration {
            found.insert(.storeKit)
        }
        return found
    }

    private struct Rule {
        let capability: Capability
        let entitlements: Set<String>
        let infoPlistKeys: Set<String>

        init(_ capability: Capability, _ entitlements: Set<String>, _ infoPlistKeys: Set<String>) {
            self.capability = capability
            self.entitlements = entitlements
            self.infoPlistKeys = infoPlistKeys
        }
    }

    private static let rules: [Rule] = [
        Rule(.healthKit, ["com.apple.developer.healthkit"], ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"]),
        Rule(.pushNotifications, ["aps-environment"], []),
        Rule(.iCloud, ["com.apple.developer.icloud-services", "com.apple.developer.icloud-container-identifiers", "com.apple.developer.ubiquity-kvstore-identifier"], []),
        Rule(.associatedDomains, ["com.apple.developer.associated-domains"], []),
        Rule(.contacts, [], ["NSContactsUsageDescription"]),
        Rule(.calendars, [], ["NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription"]),
        Rule(.photos, [], ["NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"]),
        Rule(.reminders, [], ["NSRemindersUsageDescription", "NSRemindersFullAccessUsageDescription"]),
    ]
}
