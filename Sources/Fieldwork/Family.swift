// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The Fieldwork tools installed together: one tool's `install` runs the others' installs, so a single command sets up all of them.
///
/// The consumer passes every member, itself included, and calls ``install(members:caller:flags:environment:besideDirectory:launch:)`` after its own install. A member that is not found, on PATH or beside the caller's binary, is skipped without a word. A member runs once at most: the one it starts sees `FIELDWORK_FAMILY_INSTALL` and installs only itself.
public struct Family: Sendable {
    private init() {}
}

public extension Family {
    /// The environment variable a member's install is started with, holding the caller's name; where it is already set, the family step runs nothing.
    static let environmentVariable = "FIELDWORK_FAMILY_INSTALL"

    /// A tool of the family and the arguments that make its binary install.
    struct Member: Equatable, Sendable {
        public var tool: FieldworkTool
        /// The arguments before the selection flags: `["install"]` by default.
        public var installPrefix: [String]

        public init(tool: FieldworkTool, installPrefix: [String] = ["install"]) {
            self.tool = tool
            self.installPrefix = installPrefix
        }

        /// The arguments to start this member's install with: the prefix, `--agent <name>` per agent in order, then `--all`, `--yes` and `--dry-run` where set. Tool-specific flags are never passed.
        public func installArguments(for flags: AgentSelection.Flags) -> [String] {
            var arguments = installPrefix
            for agent in flags.agents {
                arguments += ["--agent", agent.rawValue]
            }
            if flags.all {
                arguments.append("--all")
            }
            if flags.yes {
                arguments.append("--yes")
            }
            if flags.dryRun {
                arguments.append("--dry-run")
            }
            return arguments
        }
    }

    /// What running one member's install came to.
    struct Result: Equatable, Sendable {
        public var member: String
        /// The path that was run.
        public var executable: String
        public var arguments: [String]
        /// The member's exit status; 127 where it could not be launched.
        public var exitStatus: Int32
        /// Why it could not be launched, `nil` where it ran.
        public var launchFailure: String?

        public var succeeded: Bool {
            launchFailure == nil && exitStatus == 0
        }
    }

    /// Runs a program with the terminal's own streams, waits for it, and returns its exit status; throws where it cannot be launched. Injectable so a test can run fake members.
    typealias Launch = @Sendable (_ executable: String, _ arguments: [String], _ environment: [String: String]) throws -> Int32

    /// Runs the install of every member found, except `caller`, in the order given, and returns one result per member that ran.
    ///
    /// A member is found on PATH (`environment["PATH"]`), then in `besideDirectory`, the directory of the caller's own binary. One not found is skipped silently. Where `environment` already holds ``environmentVariable``, nothing runs.
    static func install(
        members: [Member],
        caller: FieldworkTool,
        flags: AgentSelection.Flags,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        besideDirectory: String? = nil,
        launch: Launch = Family.launchInheritingTerminal
    ) -> [Result] {
        guard environment[environmentVariable] == nil else { return [] }
        var childEnvironment = environment
        childEnvironment[environmentVariable] = caller.name
        var results: [Result] = []
        for member in members where member.tool.name != caller.name {
            guard let executable = find(member.tool.name, environment: environment, besideDirectory: besideDirectory) else { continue }
            let arguments = member.installArguments(for: flags)
            do {
                let status = try launch(executable, arguments, childEnvironment)
                results.append(Result(member: member.tool.name, executable: executable, arguments: arguments, exitStatus: status, launchFailure: nil))
            } catch {
                results.append(Result(member: member.tool.name, executable: executable, arguments: arguments, exitStatus: 127, launchFailure: "\(error)"))
            }
        }
        return results
    }

    /// The default launch: the child shares this process's stdin, stdout and stderr, and is waited for with no deadline, since the user may be answering its prompt.
    @Sendable
    static func launchInheritingTerminal(_ executable: String, _ arguments: [String], _ environment: [String: String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func find(_ name: String, environment: [String: String], besideDirectory: String?) -> String? {
        if let onPath = InvokedBinary.onPath(name, environment: environment) {
            return onPath
        }
        guard let besideDirectory else { return nil }
        let candidate = URL(fileURLWithPath: besideDirectory, isDirectory: true).appendingPathComponent(name).path
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: candidate) else { return nil }
        return candidate
    }
}
