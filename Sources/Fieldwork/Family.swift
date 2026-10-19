// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Darwin
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
        /// The member's exit status, as a shell reports it: its exit code, or `128 +` the signal number where a signal ended it (130 for `SIGINT`); 127 where it could not be launched.
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

    /// The default launch: the child shares this process's stdin, stdout and stderr and its process group, and is waited for with no deadline, since the user may be answering its prompt.
    ///
    /// The child stays in the caller's process group, the terminal's foreground one, so it can read the terminal without being stopped, and a Ctrl-C reaches it. It starts with the default handling of `SIGINT` and `SIGQUIT`, while this process ignores both until the child has exited and then restores what it had, as `system(3)` does: a Ctrl-C at the member's prompt is the member's to answer, and the caller carries on with its result. File descriptors other than 0, 1 and 2 are not passed on. A child ended by a signal returns `128 +` the signal number.
    @Sendable
    static func launchInheritingTerminal(_ executable: String, _ arguments: [String], _ environment: [String: String]) throws -> Int32 {
        var attributes: posix_spawnattr_t?
        try check(posix_spawnattr_init(&attributes), "posix_spawnattr_init", executable)
        defer { posix_spawnattr_destroy(&attributes) }
        var defaulted = sigset_t()
        sigemptyset(&defaulted)
        sigaddset(&defaulted, SIGINT)
        sigaddset(&defaulted, SIGQUIT)
        var unmasked = sigset_t()
        sigemptyset(&unmasked)
        try check(posix_spawnattr_setsigdefault(&attributes, &defaulted), "posix_spawnattr_setsigdefault", executable)
        try check(posix_spawnattr_setsigmask(&attributes, &unmasked), "posix_spawnattr_setsigmask", executable)
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT)), "posix_spawnattr_setflags", executable)

        var actions: posix_spawn_file_actions_t?
        try check(posix_spawn_file_actions_init(&actions), "posix_spawn_file_actions_init", executable)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for descriptor in Int32(0) ... 2 {
            try check(posix_spawn_file_actions_addinherit_np(&actions, descriptor), "posix_spawn_file_actions_addinherit_np", executable)
        }

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        TerminalSignals.shared.ignore()
        defer { TerminalSignals.shared.restore() }
        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable, &actions, &attributes, argv, envp)
        guard spawned == 0 else { throw LaunchFailure(executable: executable, call: "posix_spawn", code: spawned) }
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            let code = errno
            guard code == EINTR else { throw LaunchFailure(executable: executable, call: "waitpid", code: code) }
        }
        return exitStatus(fromWaitStatus: status)
    }

    /// A `waitpid` status as a shell reports it: the exit code where the child exited, `128 +` the signal number where a signal ended it.
    internal static func exitStatus(fromWaitStatus status: Int32) -> Int32 {
        let signal = status & 0x7F
        return signal == 0 ? (status >> 8) & 0xFF : 128 + signal
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

/// A launch that could not start its child, or lost track of it: the call that failed and why.
struct LaunchFailure: Error, CustomStringConvertible {
    var executable: String
    var call: String
    var code: Int32

    var description: String {
        "\(call) failed for \(executable): \(String(cString: strerror(code))) (errno \(code))"
    }
}

private func check(_ code: Int32, _ call: String, _ executable: String) throws {
    guard code == 0 else { throw LaunchFailure(executable: executable, call: call, code: code) }
}

/// This process's handling of `SIGINT` and `SIGQUIT` while a member runs: ignored from the first launch that starts until the last one running ends, then put back as it was.
///
/// Counted so that two launches that overlap cannot leave the process ignoring Ctrl-C: the second would otherwise save the ignored handling the first set, and put it back last.
private final class TerminalSignals: @unchecked Sendable {
    static let shared = TerminalSignals()

    private let lock = NSLock()
    private var running = 0
    private var savedInterrupt = sigaction()
    private var savedQuit = sigaction()

    func ignore() {
        lock.lock()
        defer { lock.unlock() }
        running += 1
        guard running == 1 else { return }
        var ignored = sigaction()
        ignored.__sigaction_u.__sa_handler = SIG_IGN
        sigemptyset(&ignored.sa_mask)
        sigaction(SIGINT, &ignored, &savedInterrupt)
        sigaction(SIGQUIT, &ignored, &savedQuit)
    }

    func restore() {
        lock.lock()
        defer { lock.unlock() }
        running -= 1
        guard running == 0 else { return }
        sigaction(SIGINT, &savedInterrupt, nil)
        sigaction(SIGQUIT, &savedQuit, nil)
    }
}
