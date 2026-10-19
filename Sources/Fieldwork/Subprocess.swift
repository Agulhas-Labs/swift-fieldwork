// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Spawns a child process and returns what it said, bounded on every path out.
///
/// The child only is signalled when it passes its deadline: anything it started is not, and the pipes are drained against a deadline precisely so that a survivor holding one open cannot extend the wait.
public struct Subprocess {
    /// How long any one spawn may take before it is ended and reported as timed out, in seconds of wall clock.
    ///
    /// Generous for the work, because the number is not a performance budget but the point at which a wedged service stops being worth waiting for. What it bounds is stated on the type.
    public static var defaultDeadline: TimeInterval {
        5
    }

    /// The child ``run(_:_:deadline:in:environment:grace:ready:)`` starts, its standard input the null device.
    ///
    /// **Never this process's own standard input.** A tool's install asks its questions on the terminal and then spawns another command; a child handed that terminal, in a process group that is not the terminal's foreground one, is stopped the moment it touches it, and waited on until its deadline. Every child here is asked a question by its arguments, never by a person.
    static func process(_ executable: String, _ arguments: [String], in directory: URL?, environment: [String: String]?) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        return process
    }

    /// Spawns a child and returns what it said.
    ///
    /// **Bounded, on every path out.** The wait for exit is a deadline rather than a `waitUntilExit`, the child is ended when it expires, and the pipes are drained on the reader's own queue rather than by a `readDataToEndOfFile` on this thread — because a grandchild that inherited the write end holds the pipe open long after the child is gone, and a read of it would extend a bounded wait into an unbounded one. What comes back from an expired call is a failed ``Output`` whose standard error says it timed out, which a caller reads as a call that did not succeed.
    ///
    /// - Parameters:
    ///   - deadline: how long the child may take before it is ended, in seconds of wall clock. Where `ready` is given, the clock starts when the child is ready rather than at launch, so the call also spends up to the readiness wait (thirty seconds) before it. The call itself returns within `deadline` plus a short grace for its read ends to close, and when the child is ended, plus the two short grace windows it is given to die in as well.
    ///   - directory: where the child is started, for a caller whose arguments are only correct relative to a directory of its own — a relative `-project` path, say. The host's own working directory where `nil`.
    ///   - environment: the child's whole environment, for a caller that must ask as another command would run. This process's own where `nil`.
    ///   - grace: how long an ended child is given to die after each signal, in seconds. The short fixed grace where `nil`; a test that needs the polite signal to be the one that ends the child, however slowly its handler runs, passes a long one.
    ///   - ready: text on the child's standard output that says it is set up, for a test whose child must be listening before the deadline can matter. The deadline's clock starts when the text shows, when the child exits, or after thirty seconds, whichever comes first; `nil` starts it at once.
    public static func run(
        _ executable: String,
        _ arguments: [String],
        deadline: TimeInterval = defaultDeadline,
        in directory: URL? = nil,
        environment: [String: String]? = nil,
        grace: TimeInterval? = nil,
        ready marker: String? = nil
    ) throws -> Output {
        let process = process(executable, arguments, in: directory, environment: environment)
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let exited = DispatchSemaphore(value: 0)
        let readiness = marker.map { SpawnStreams.Readiness(marker: Data($0.utf8)) }
        process.terminationHandler = { _ in
            exited.signal()
            readiness?.seen.signal()
        }
        var started = Date()
        do {
            try process.run()
        } catch {
            ProcessStreams.abandon(output, errors)
            throw error
        }
        // Read from here on: what the child writes before the handlers are in place waits in the pipe for them.
        let streams = SpawnStreams(standardOutput: output, standardError: errors, readiness: readiness)
        var ready = false
        if let readiness {
            ready = readiness.seen.wait(timeout: .now() + readinessLimit) == .success
            started = Date()
        }
        guard exited.wait(timeout: .now() + deadline) == .success else {
            end(process, exited: exited, grace: grace ?? terminationGrace)
            let collected = streams.collected()
            let name = URL(fileURLWithPath: executable).lastPathComponent
            // Where the readiness wait ran out, the clock started without the marker, so the message says that instead.
            let counted = readiness == nil ? "" : ready ? " of being ready" : " after its \(seconds(readinessLimit)) wait to be ready ran out"
            return Output(
                succeeded: false,
                standardOutput: collected.standardOutput,
                standardError: "\(collected.standardError)the spawn timed out: \(name) did not finish within \(seconds(deadline))\(counted) and was ended"
            )
        }
        // Exit is not end of output: the handlers may still owe the last bytes, and a grandchild may owe them
        // forever. What is left of the deadline is what they get.
        streams.waitForEnd(within: deadline - Date().timeIntervalSince(started))
        let collected = streams.collected()
        return Output(succeeded: process.terminationStatus == 0, standardOutput: collected.standardOutput, standardError: collected.standardError)
    }

    /// Ends a child that has passed its deadline: the polite signal, a moment to take it, then the one it cannot ignore.
    ///
    /// The second wait is what makes the child *gone* rather than merely signalled by the time this returns — a process that ignores `SIGTERM` would otherwise outlive the call that gave up on it. The child only: anything it started is not signalled, for the reason the type states, and the pipes are drained against a deadline precisely so that a survivor holding one open cannot extend the wait.
    static func end(_ process: Process, exited: DispatchSemaphore, grace: TimeInterval = terminationGrace) {
        let pid = process.processIdentifier
        process.terminate()
        guard exited.wait(timeout: .now() + grace) != .success else {
            return
        }
        kill(pid, SIGKILL)
        _ = exited.wait(timeout: .now() + grace)
    }

    /// The longest a spawn that was told to wait for its child's readiness waits for it, in seconds, before the deadline's clock starts regardless.
    static var readinessLimit: TimeInterval {
        30
    }

    /// How long an ended child is given to die, in seconds — once after `SIGTERM` and once after `SIGKILL`.
    static var terminationGrace: TimeInterval {
        0.25
    }

    /// A duration as a sentence says it: `5s`, `0.5s`.
    static func seconds(_ interval: TimeInterval) -> String {
        interval == interval.rounded() ? "\(Int(interval))s" : "\(interval)s"
    }
}

public extension Subprocess {
    /// What a spawned tool said, down to the three things this reads.
    struct Output: Equatable, Sendable {
        public let succeeded: Bool
        public let standardOutput: String
        /// What the tool printed on the way to failing — the only thing that says *which* failure it was, and what a run that timed out reports itself through.
        public let standardError: String

        public init(succeeded: Bool, standardOutput: String, standardError: String = "") {
            self.succeeded = succeeded
            self.standardOutput = standardOutput
            self.standardError = standardError
        }

        /// What a failed run said, its error before its output: the first line, then each line of a `Caused by:` chain after it.
        ///
        /// A tool often puts the reason under its first line (`Error: failed to load configuration`, then `Caused by:` and the cause), so the first line alone names a failure without its cause.
        public var failureReason: String {
            guard let said = [standardError, standardOutput].first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                return "no output"
            }
            let lines = said.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            var reason = [lines[0]]
            if let causes = lines.firstIndex(of: "Caused by:") {
                reason += lines[(causes + 1)...]
            }
            return reason.joined(separator: ": ")
        }
    }
}
