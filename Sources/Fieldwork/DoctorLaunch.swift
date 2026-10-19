// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

public extension DoctorProbe {
    /// What a launcher does: runs `binary` with `arguments`, `input` on its stdin and `environment`, and returns its exit status and stdout, or `nil` where it could not be started or was not done within `limit` seconds. Stderr is discarded.
    typealias Launcher = @Sendable (_ binary: URL, _ arguments: [String], _ input: Data, _ environment: [String: String], _ limit: TimeInterval) -> (status: Int32, output: Data)?

    /// What a child of `binary` run with `arguments` wrote to stdout and the status it exited with, given `input` on stdin, or `nil` where it could not be launched or was not done within `limit` seconds.
    ///
    /// A child still running at that deadline is stopped and reaped before this returns. This is the probe's default launcher.
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
        guard let output = exchange(input, writing: stdin.fileHandleForWriting, reading: stdout.fileHandleForReading, until: deadline),
              exited.wait(timeout: deadline) == .success
        else {
            stop(process, exited: exited)
            return nil
        }
        return (process.terminationStatus, output)
    }

    /// `input` written to a child and its output read to the end on a thread of their own, or `nil` where that is not done by `deadline`.
    ///
    /// That thread closes both ends once it is done, so a child stopped at the deadline leaves neither behind, and one whose ends outlive it holds that thread and never the run.
    private static func exchange(_ input: Data, writing: FileHandle, reading: FileHandle, until deadline: DispatchTime) -> Data? {
        let done = DispatchSemaphore(value: 0)
        let reply = ExchangedReply()
        DispatchQueue.global(qos: .userInitiated).async {
            // The child reads its stdin to the end before it writes, so writing all of it first cannot wait on a full stdout.
            try? writing.write(contentsOf: input)
            try? writing.close()
            reply.set((try? reading.readToEnd()) ?? Data())
            try? reading.close()
            done.signal()
        }
        guard done.wait(timeout: deadline) == .success else { return nil }
        return reply.value
    }

    /// A child past its deadline asked to terminate, killed where it is still running a second later, and waited on until it is reaped.
    private static func stop(_ process: Process, exited: DispatchSemaphore) {
        process.terminate()
        guard exited.wait(timeout: .now() + 1) == .timedOut else { return }
        kill(process.processIdentifier, SIGKILL)
        _ = exited.wait(timeout: .now() + 10)
    }
}

private extension DoctorProbe {
    /// The output a child wrote, handed from the thread that read it to the one waiting on it.
    final class ExchangedReply: @unchecked Sendable {
        private let lock = NSLock()
        private var data: Data?

        var value: Data? {
            lock.withLock { data }
        }

        func set(_ output: Data) {
            lock.withLock { data = output }
        }
    }
}
