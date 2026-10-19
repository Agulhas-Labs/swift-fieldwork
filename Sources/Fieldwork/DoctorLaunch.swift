// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension DoctorProbe {
    /// What a launcher does: runs `binary` with `arguments`, `input` on its stdin and `environment`, and returns its exit status and stdout, or `nil` where it could not be started or was not done within `limit` seconds.
    ///
    /// Stderr is discarded.
    typealias Launcher = @Sendable (_ binary: URL, _ arguments: [String], _ input: Data, _ environment: [String: String], _ limit: TimeInterval) -> (status: Int32, output: Data)?

    /// What a child of `binary` run with `arguments` wrote to stdout and the status it exited with, given `input` on stdin, or `nil` where it could not be launched or was not done within `limit` seconds.
    ///
    /// A child still running at that deadline is stopped and reaped before this returns, and so is every process left in its process group, a grandchild still holding its stdout or one it left running in the background, so that end of the pipe is closed too. This is the probe's default launcher.
    ///
    /// The child leads a process group of its own, so a signal that stops the caller, a SIGTERM or a Ctrl-C at the terminal, does not reach it: a caller that needs it to injects a launcher of its own.
    static func launch(
        _ binary: URL,
        arguments: [String],
        input: Data = Data(),
        environment: [String: String]? = nil,
        within limit: TimeInterval
    ) -> (status: Int32, output: Data)? {
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        let (stdin, stdout) = (Pipe(), Pipe())
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        // A child that exits before reading all of it is a write error then, not a SIGPIPE that takes this process down.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let launched = (try? process.run()) != nil
        // Every end is closed here rather than left to deallocation, which a run of thousands of calls outruns until
        // no descriptor is left for the next child: the child's own ends at once, launched or not, and this side's
        // too where no child was launched to talk to.
        for end in [stdin.fileHandleForReading, stdout.fileHandleForWriting] {
            try? end.close()
        }
        guard launched else {
            for end in [stdin.fileHandleForWriting, stdout.fileHandleForReading] {
                try? end.close()
            }
            return nil
        }
        let deadline = DispatchTime.now() + limit
        let reply = exchange(input, writing: stdin.fileHandleForWriting, reading: stdout.fileHandleForReading)
        guard let output = reply.output(by: deadline), exited.wait(timeout: deadline) == .success else {
            stop(process, exited: exited)
            // With the group gone nothing holds the pipe's other end, so the read reaches it and closes this side.
            _ = reply.output(by: .now() + 10)
            return nil
        }
        return (process.terminationStatus, output)
    }

    /// `input` written to a child and its output read to the end on a thread of their own.
    ///
    /// That thread closes both ends once it is done, so a child stopped at the deadline leaves neither behind, and one whose ends outlive it holds that thread and never the run.
    private static func exchange(_ input: Data, writing: FileHandle, reading: FileHandle) -> ExchangedReply {
        let reply = ExchangedReply()
        DispatchQueue.global(qos: .userInitiated).async {
            // The child reads its stdin to the end before it writes, so writing all of it first cannot wait on a full stdout.
            try? writing.write(contentsOf: input)
            try? writing.close()
            let output = (try? reading.readToEnd()) ?? Data()
            try? reading.close()
            reply.set(output)
        }
        return reply
    }

    /// A child past its deadline and its process group asked to terminate, the group killed a second later, or as soon as the child is gone, and the child waited on until it is reaped.
    ///
    /// The group is killed even where the child exited on its own, since what it left running there can still hold its stdout.
    private static func stop(_ process: Process, exited: DispatchSemaphore) {
        let group = process.processIdentifier
        killpg(group, SIGTERM)
        let reaped = exited.wait(timeout: .now() + 1) == .success
        killpg(group, SIGKILL)
        if !reaped {
            _ = exited.wait(timeout: .now() + 10)
        }
    }
}

private extension DoctorProbe {
    /// The output a child wrote, handed from the thread that read it to the one waiting on it, once that thread has closed both ends.
    final class ExchangedReply: @unchecked Sendable {
        private let lock = NSLock()
        private let done = DispatchSemaphore(value: 0)
        private var data: Data?

        /// The output, or `nil` where it is not all read by `deadline`; a later call waits again.
        func output(by deadline: DispatchTime) -> Data? {
            guard done.wait(timeout: deadline) == .success else { return nil }
            done.signal()
            return lock.withLock { data }
        }

        func set(_ output: Data) {
            lock.withLock { data = output }
            done.signal()
        }
    }
}
