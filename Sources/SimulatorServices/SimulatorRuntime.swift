// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation

/// One installed simulator runtime, as `xcrun simctl list runtimes -j` describes it.
public struct SimulatorRuntime: Decodable, Sendable, Equatable {
    /// The runtime identifier, such as `com.apple.CoreSimulator.SimRuntime.iOS-27-0`.
    public let identifier: String
    /// The marketing version, such as `27.0`.
    public let version: String
    /// The build, such as `24A434`.
    public let buildversion: String
    /// The directory holding the runtime's root file system.
    public let runtimeRoot: String
    /// Whether the runtime can be used on this machine.
    public let isAvailable: Bool

    /// Decodes the `{"runtimes":[...]}` shape `simctl` prints, ignoring keys it does not know.
    public static func parseList(_ json: Data) throws -> [SimulatorRuntime] {
        try JSONDecoder().decode(Listing.self, from: json).runtimes
    }

    /// The runtimes installed on this machine; throws where `simctl` fails.
    public static func installed() throws -> [SimulatorRuntime] {
        let arguments = ["simctl", "list", "runtimes", "-j"]
        let output = try Subprocess.run("/usr/bin/xcrun", arguments, deadline: 30)
        guard output.succeeded else {
            throw SimulatorServicesError.commandFailed(command: "xcrun simctl list runtimes -j", standardError: output.standardError)
        }
        return try parseList(Data(output.standardOutput.utf8))
    }

    private struct Listing: Decodable {
        let runtimes: [SimulatorRuntime]
    }
}
