// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
@testable import SimulatorServices
import Testing

/// A project's entitlements, usage descriptions and StoreKit file say which capabilities it needs.
struct ProjectDeclarationsTests {
    @Test
    func keysIgnoreBooleanFalse() throws {
        let keys = try ProjectDeclarations.keys(ofPlist: Data(contentsOf: fixture("entitlements.plist")))
        #expect(keys == ["com.apple.developer.healthkit", "aps-environment", "com.apple.developer.associated-domains"])
    }

    @Test
    func readsBinaryPlists() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["aps-environment": "production", "off": false], format: .binary, options: 0)
        #expect(try ProjectDeclarations.keys(ofPlist: data) == ["aps-environment"])
    }

    @Test
    func declarationsMapToCapabilities() throws {
        let declarations = try ProjectDeclarations.read(
            entitlements: fixture("entitlements.plist"),
            infoPlist: fixture("Info.plist"),
            storeKitConfiguration: true
        )
        #expect(declarations.capabilities == [.healthKit, .pushNotifications, .associatedDomains, .storeKit, .contacts, .photos, .reminders])
    }

    @Test
    func aFalseUsageDescriptionAndFalseEntitlementAreIgnored() throws {
        let declarations = try ProjectDeclarations.read(entitlements: fixture("entitlements.plist"), infoPlist: fixture("Info.plist"), storeKitConfiguration: false)
        #expect(!declarations.capabilities.contains(.iCloud))
        #expect(!declarations.capabilities.contains(.calendars))
        #expect(!declarations.capabilities.contains(.storeKit))
    }

    @Test
    func healthUsageDescriptionAloneImpliesHealthKit() {
        #expect(ProjectDeclarations(infoPlistKeys: ["NSHealthUpdateUsageDescription"]).capabilities == [.healthKit])
    }

    @Test
    func iCloudComesFromAnyOfItsThreeKeys() {
        for key in ["com.apple.developer.icloud-services", "com.apple.developer.icloud-container-identifiers", "com.apple.developer.ubiquity-kvstore-identifier"] {
            #expect(ProjectDeclarations(entitlements: [key]).capabilities == [.iCloud])
        }
    }

    @Test
    func noFilesMeansNoCapabilities() throws {
        let declarations = try ProjectDeclarations.read(entitlements: nil, infoPlist: nil, storeKitConfiguration: false)
        #expect(declarations == ProjectDeclarations())
        #expect(declarations.capabilities.isEmpty)
    }
}
