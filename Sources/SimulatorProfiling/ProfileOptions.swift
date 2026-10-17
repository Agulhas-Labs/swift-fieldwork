// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SimulatorServices

/// A command line `simulator-profile` cannot use.
public struct ProfileUsageError: Error, Equatable {
    public let message: String
}

/// Which stages of the evaluation run.
public enum ProfileStage: String, Equatable, Sendable {
    /// The cost stage, then the health stage.
    case all
    /// Boot a stock device and measure what each service costs.
    case cost
    /// Check, on a profile the cost stage wrote, that a device runs with the candidates off.
    case health
}

/// The arguments of `simulator-profile`.
public struct ProfileOptions: Equatable, Sendable {
    public var runtime: String
    public var deviceType: String
    public var output: String
    public var window = 300
    public var footprintThresholdMB = 4.0
    public var cpuThresholdSeconds = 0.5
    public var profileVersion = 1
    public var allowBooted = false
    public var app: String?
    public var bundleID: String?
    public var xctestrun: String?
    public var onlyTesting: String?
    public var logWindow = 45
    public var maxKept = 12
    public var baselines = 3
    public var stage = ProfileStage.all
    public var from: String?
    public var candidates: [String]?
    public var swift: String?
    public var keep: [Capability] = []

    /// The usage text.
    public static let usage = """
    usage: simulator-profile --runtime <identifier> --device-type <name> --out <path.json>
                             [--window 300] [--footprint-threshold 4] [--cpu-threshold 0.5]
                             [--profile-version 1] [--allow-booted]
                             [--stage all|cost|health] [--from <profile.json>]
                             [--app <path.app> --bundle-id <id>] [--xctestrun <path> --only-testing <id>]
                             [--log-window 45] [--max-kept 12] [--baselines 3] [--candidates <label,label,...>]
                             [--keep <capability,capability,...>] [--swift <path.swift>]
    """

    private static let valued: Set = [
        "--runtime", "--device-type", "--out", "--window", "--footprint-threshold", "--cpu-threshold", "--profile-version",
        "--app", "--bundle-id", "--xctestrun", "--only-testing", "--log-window", "--max-kept", "--baselines", "--stage", "--from", "--candidates", "--keep", "--swift",
    ]

    /// Parses the arguments after the program name.
    public static func parse(_ arguments: [String]) throws -> ProfileOptions {
        var values: [String: String] = [:]
        var allowBooted = false
        var index = 0
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
        try options.applyNumbers(values)
        try options.applyPaths(values)
        try options.validate()
        return options
    }

    private mutating func applyNumbers(_ values: [String: String]) throws {
        if let text = values["--window"] {
            window = try Self.number(Int(text), "--window", text, atLeast: 1)
        }
        if let text = values["--profile-version"] {
            profileVersion = try Self.number(Int(text), "--profile-version", text, atLeast: 1)
        }
        if let text = values["--footprint-threshold"] {
            footprintThresholdMB = try Self.number(Double(text), "--footprint-threshold", text, atLeast: 0)
        }
        if let text = values["--cpu-threshold"] {
            cpuThresholdSeconds = try Self.number(Double(text), "--cpu-threshold", text, atLeast: 0)
        }
        if let text = values["--log-window"] {
            logWindow = try Self.number(Int(text), "--log-window", text, atLeast: 1)
        }
        if let text = values["--max-kept"] {
            maxKept = try Self.number(Int(text), "--max-kept", text, atLeast: 1)
        }
        if let text = values["--baselines"] {
            baselines = try Self.number(Int(text), "--baselines", text, atLeast: 1)
        }
    }

    private mutating func applyPaths(_ values: [String: String]) throws {
        app = values["--app"]
        bundleID = values["--bundle-id"]
        xctestrun = values["--xctestrun"]
        onlyTesting = values["--only-testing"]
        from = values["--from"]
        swift = values["--swift"]
        if let text = values["--stage"] {
            guard let chosen = ProfileStage(rawValue: text) else { throw ProfileUsageError(message: "--stage needs all, cost or health, not \(text)") }
            stage = chosen
        }
        if let text = values["--candidates"] {
            let labels = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !labels.isEmpty else { throw ProfileUsageError(message: "--candidates needs at least one label") }
            candidates = labels
        }
        if let text = values["--keep"] {
            keep = try Self.capabilities(text)
        }
    }

    private static func capabilities(_ text: String) throws -> [Capability] {
        let names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { throw ProfileUsageError(message: "--keep needs at least one capability") }
        return try names.map { name in
            guard let capability = Capability(rawValue: name) else {
                let valid = Capability.allCases.map(\.rawValue).joined(separator: ", ")
                throw ProfileUsageError(message: "--keep names \(name), which is not a capability; the capabilities are \(valid)")
            }
            return capability
        }
    }

    private func validate() throws {
        if (app == nil) != (bundleID == nil) {
            throw ProfileUsageError(message: "--app and --bundle-id go together")
        }
        if (xctestrun == nil) != (onlyTesting == nil) {
            throw ProfileUsageError(message: "--xctestrun and --only-testing go together")
        }
        if stage == .health, from == nil {
            throw ProfileUsageError(message: "--stage health needs --from <profile.json>")
        }
        if stage != .health, from != nil {
            throw ProfileUsageError(message: "--from is only for --stage health")
        }
    }

    private static func number<T: Comparable>(_ value: T?, _ flag: String, _ text: String, atLeast minimum: T) throws -> T {
        guard let value, value >= minimum else { throw ProfileUsageError(message: "\(flag) needs a number of at least \(minimum), not \(text)") }
        return value
    }
}
