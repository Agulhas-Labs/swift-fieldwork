// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers the one helper every subprocess here reads its output through.
///
/// It lives in a file of its own rather than beside a caller because every caller depends on it, and a private helper on whichever type noticed the bug would leave the others deadlocking on identical code.
struct ProcessStreamsTests {
    /// A child that fills one pipe before it touches the other is read to the end all the same, rather than deadlocking the command that is waiting on it.
    ///
    /// A pipe holds 64 KB. Draining stdout to EOF first means a child with more than that to say on stderr blocks in `write` while this side blocks in `read` — forever, with no timeout, on a path a caller waits on synchronously. A real tool cannot be made to produce that on demand, so the child here is written to order: 200 KB to stderr, past the buffer three times over, and only then a byte on stdout.
    ///
    /// The drain runs on a thread of its own and is *waited* on with a deadline, rather than being called here and trusted to return. Both halves of that are the point. `readDataToEndOfFile` is a blocking read that no task cancellation reaches, so `.timeLimit` cannot end it and the wrong ordering would hang the whole suite instead of failing this test — a gate that never reports is worse than none. And the child is killed when the deadline passes, which closes the write ends and lets the stuck reader finish, so a regression costs ten seconds and one failure rather than a wedged process for the rest of the run.
    ///
    /// **A `Thread`, not `DispatchQueue.global()`**: a dispatched block has to be *given* a worker, and in a suite that stands up fixture packages the pool can have none to give for longer than this deadline — so the block never runs, the deadline passes, and the test reports a deadlock in code that is working. A harness measuring whether something starts within ten seconds must not itself queue behind the load. `ProcessStreams.drain` makes the same choice for the same reason, where the failure would be a hang rather than a false failure.
    @Test
    func aChildFillingStderrFirstIsStillReadToTheEnd() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "for i in $(seq 1 2000); do printf '%0100d\\n' $i >&2; done; printf 'done\\n'"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let drained = Drained()
        let finished = DispatchSemaphore(value: 0)
        let reader = Thread {
            drained.streams = ProcessStreams.drain(stdout: stdout, stderr: stderr)
            finished.signal()
        }
        reader.start()
        let returned = finished.wait(timeout: .now() + 10) == .success
        if !returned {
            process.terminate()
        }
        process.waitUntilExit()

        #expect(returned, "reading one stream to the end before the other deadlocks on a child that fills it")
        let streams = try #require(drained.streams)
        #expect(String(bytes: streams.output, encoding: .utf8) == "done\n")
        #expect(streams.failure.count > 200_000)
        #expect(process.terminationStatus == 0)
    }

    /// The mirror case, because a fix that only reads stderr early would pass the test above and fail this one.
    ///
    /// Here the child fills *stdout* past the buffer before saying anything on stderr. Both orderings have to survive, since which stream a subprocess fills first is its business — a file listing on a monorepo fills stdout, a refusal's usage advice fills stderr.
    @Test
    func aChildFillingStdoutFirstIsAlsoReadToTheEnd() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "for i in $(seq 1 2000); do printf '%0100d\\n' $i; done; printf 'oops\\n' >&2"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let drained = Drained()
        let finished = DispatchSemaphore(value: 0)
        let reader = Thread {
            drained.streams = ProcessStreams.drain(stdout: stdout, stderr: stderr)
            finished.signal()
        }
        reader.start()
        let returned = finished.wait(timeout: .now() + 10) == .success
        if !returned {
            process.terminate()
        }
        process.waitUntilExit()

        #expect(returned, "a child filling stdout past the pipe buffer must not deadlock either")
        let streams = try #require(drained.streams)
        #expect(streams.output.count > 200_000)
        #expect(String(bytes: streams.failure, encoding: .utf8) == "oops\n")
        #expect(process.terminationStatus == 0)
    }
}

private extension ProcessStreamsTests {
    /// What the drain returned, handed back from the thread that waited on it.
    ///
    /// Unchecked because the semaphore is the ordering: the write happens before the signal and the read after the wait, and on the deadline path the value is only ever read as `nil`.
    final class Drained: @unchecked Sendable {
        var streams: (output: Data, failure: Data)?
    }
}
