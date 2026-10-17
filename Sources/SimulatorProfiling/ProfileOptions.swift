// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A command line `simulator-profile` cannot use.
public struct ProfileUsageError: Error, Equatable {
    public let message: String
}

/// The arguments of `simulator-profile`.
public struct ProfileOptions: Equatable {
    public var runtime: String
    public var deviceType: String
    public var output: String
    public var window = 300
    public var footprintThresholdMB = 4.0
    public var cpuThresholdSeconds = 0.5
    public var profileVersion = 1
    public var allowBooted = false

    /// The usage text.
    public static let usage = """
    usage: simulator-profile --runtime <identifier> --device-type <name> --out <path.json>
                             [--window 300] [--footprint-threshold 4] [--cpu-threshold 0.5]
                             [--profile-version 1] [--allow-booted]
    """

    /// Parses the arguments after the program name.
    public static func parse(_ arguments: [String]) throws -> ProfileOptions {
        var values: [String: String] = [:]
        var allowBooted = false
        var index = 0
        let valued: Set = ["--runtime", "--device-type", "--out", "--window", "--footprint-threshold", "--cpu-threshold", "--profile-version"]
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--allow-booted" {
                allowBooted = true
            } else if valued.contains(flag) {
                guard index + 1 < arguments.count else { throw ProfileUsageError(message: "\(flag) needs a value") }
                index += 1
                values[flag] = arguments[index]
            } else {
                throw ProfileUsageError(message: "unknown argument \(flag)")
            }
            index += 1
        }
        guard let runtime = values["--runtime"] else { throw ProfileUsageError(message: "--runtime is required") }
        guard let deviceType = values["--device-type"] else { throw ProfileUsageError(message: "--device-type is required") }
        guard let output = values["--out"] else { throw ProfileUsageError(message: "--out is required") }
        var options = ProfileOptions(runtime: runtime, deviceType: deviceType, output: output)
        options.allowBooted = allowBooted
        if let text = values["--window"] {
            options.window = try number(Int(text), "--window", text, atLeast: 1)
        }
        if let text = values["--profile-version"] {
            options.profileVersion = try number(Int(text), "--profile-version", text, atLeast: 1)
        }
        if let text = values["--footprint-threshold"] {
            options.footprintThresholdMB = try number(Double(text), "--footprint-threshold", text, atLeast: 0)
        }
        if let text = values["--cpu-threshold"] {
            options.cpuThresholdSeconds = try number(Double(text), "--cpu-threshold", text, atLeast: 0)
        }
        return options
    }

    private static func number<T: Comparable>(_ value: T?, _ flag: String, _ text: String, atLeast minimum: T) throws -> T {
        guard let value, value >= minimum else { throw ProfileUsageError(message: "\(flag) needs a number of at least \(minimum), not \(text)") }
        return value
    }
}
