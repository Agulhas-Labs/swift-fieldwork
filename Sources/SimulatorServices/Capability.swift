// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A system capability an app can use, and so a set of simulator services it may need.
public enum Capability: String, Codable, CaseIterable, Sendable {
    case healthKit
    case pushNotifications
    case iCloud
    case associatedDomains
    case storeKit
    case contacts
    case calendars
    case photos
    case reminders

    /// The labels in `jobs` that serve `capability`, sorted.
    public static func labels(for capability: Capability, in jobs: [LaunchJob]) -> [String] {
        let rule = capability.rule
        return jobs.map(\.label).filter { rule.matches($0) }.sorted()
    }

    /// Label stems that match a label equal to them or starting with them and a dot, and stems that match only a label equal to them.
    private struct Rule {
        var stems: [String]
        var exactStems: [String] = []

        func matches(_ label: String) -> Bool {
            exactStems.contains(label) || stems.contains { label == $0 || label.hasPrefix($0 + ".") }
        }
    }

    private var rule: Rule {
        switch self {
        case .healthKit:
            Rule(stems: ["com.apple.healthd", "com.apple.healthappd", "com.apple.healthcontentd", "com.apple.healtheventsd", "com.apple.healthrecordsd"])
        case .pushNotifications:
            Rule(stems: [], exactStems: ["com.apple.apsd"])
        case .iCloud:
            Rule(stems: [
                "com.apple.cloudd", "com.apple.bird", "com.apple.ckdiscretionaryd", "com.apple.cksharingmanagementd", "com.apple.syncdefaultsd",
                "com.apple.akd", "com.apple.protectedcloudstorage", "com.apple.security.cloudkeychainproxy3",
            ])
        case .associatedDomains:
            Rule(stems: ["com.apple.swcd"])
        case .storeKit:
            Rule(stems: ["com.apple.storekitd", "com.apple.itunesstored", "com.apple.itunescloudd", "com.apple.appstored", "com.apple.appstorecomponentsd", "com.apple.passd", "com.apple.financed"])
        case .contacts:
            Rule(stems: ["com.apple.contactsd", "com.apple.contacts"])
        case .calendars:
            Rule(stems: ["com.apple.calaccessd"])
        case .photos:
            Rule(stems: ["com.apple.assetsd", "com.apple.photoanalysisd", "com.apple.photos", "com.apple.photosface", "com.apple.cloudphotod"])
        case .reminders:
            Rule(stems: ["com.apple.remindd"])
        }
    }
}
