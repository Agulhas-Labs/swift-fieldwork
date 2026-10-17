// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The services every app needs to install, launch, read preferences, stay secure and be tested.
///
/// Switching one off breaks the app under test, not a feature it may not use, so none is a candidate for switching off; the health check still verifies everything else.
public enum InfrastructureServices {
    /// Label stems that match a label equal to them or starting with them and a dot.
    public static let stems: [String] = [
        "com.apple.lsd", "com.apple.mobile.installd", "com.apple.installcoordinationd", "com.apple.containermanagerd",
        "com.apple.runningboardd", "com.apple.frontboard", "com.apple.SpringBoard", "com.apple.backboardd",
        "com.apple.pluginkit", "com.apple.iconservices", "com.apple.FileCoordination", "com.apple.fontservicesd",
        "com.apple.pasteboard", "com.apple.securityd", "com.apple.trustd", "com.apple.tccd", "com.apple.cfprefsd",
        "com.apple.appprotectiond", "com.apple.dasd", "com.apple.nsurlsessiond", "com.apple.usernotificationsd",
        "com.apple.accountsd", "com.apple.systemstatusd", "com.apple.UserEventAgent-System", "com.apple.notifyd",
        "com.apple.distnoted", "com.apple.logd", "com.apple.diagnosticd", "com.apple.configd_sim",
        "com.apple.CoreSimulator", "com.apple.testmanagerd", "com.apple.dt",
    ]

    /// Whether `label` is one of the stems or starts with one and a dot.
    public static func matches(_ label: String) -> Bool {
        stems.contains { label == $0 || label.hasPrefix($0 + ".") }
    }
}
