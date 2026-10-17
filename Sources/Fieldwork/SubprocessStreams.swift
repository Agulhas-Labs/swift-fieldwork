// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension Subprocess {
    /// The two pipes of one spawn, drained on the reader's own queue so that neither the child nor anything it left behind can hold this thread.
    ///
    /// A `readDataToEndOfFile` here would be an unbounded wait wearing a bounded one's clothes: the end of the file is the write end being closed, and a grandchild that inherited it — a launched service, a `&`-backgrounded command — keeps it open after the child this spawned is dead. So the bytes are accumulated as they arrive and the caller takes whatever has arrived when its deadline is up.
    ///
    /// The read ends are watched by dispatch sources this owns rather than by a handle's `readabilityHandler`, because a handle given a handler duplicates its descriptor for the watch and closes that duplicate, and on a loaded machine the handle itself, only once the watch's cancellation has run — after the call that cleared the handler and closed the handle has returned. Here each read end is closed in its own source's cancel handler, the one place dispatch allows it, and the caller waits for both closes before it returns.
    ///
    /// Each read end is made non-blocking before it is watched, so that no read can hold the queue — and with it the cancel handler that closes the descriptor — for as long as a grandchild keeps the write end open: a read that finds nothing waits for the next event instead. And because a cancelled source is never handed the events still pending on it, each cancel handler reads what is left in its pipe before it closes the read end, up to ``finalReadLimit`` bytes, so that what the child wrote as it was ended is not dropped.
    final class SpawnStreams: @unchecked Sendable {
        private let lock = NSLock()
        private var standardOutput = Data()
        private var standardError = Data()
        private var open = 2
        private let ended = DispatchSemaphore(value: 0)
        private let released = DispatchSemaphore(value: 0)
        private let handles: [FileHandle]
        private var sources: [DispatchSourceRead] = []
        private let readiness: Readiness?
        private var readinessSignalled = false
        private var searchedThrough = 0
        private var scanned = 0

        /// Starts watching both read ends on `queue`, which runs every read and every close, and signals `readiness` once the marker shows on standard output.
        init(
            standardOutput: Pipe,
            standardError: Pipe,
            readiness: Readiness? = nil,
            queue: DispatchQueue = DispatchQueue(label: "Subprocess.run")
        ) {
            self.readiness = readiness
            handles = [standardOutput.fileHandleForReading, standardError.fileHandleForReading]
            sources = handles.indices.map { drain($0, on: queue) }
            for source in sources {
                source.resume()
            }
        }

        /// What has arrived so far, decoded — and, for the caller that timed out, the last thing this reads.
        func collected() -> (standardOutput: String, standardError: String) {
            stop()
            lock.lock()
            defer { lock.unlock() }
            return (String(bytes: standardOutput, encoding: .utf8) ?? "", String(bytes: standardError, encoding: .utf8) ?? "")
        }

        /// Waits for both pipes to reach end of file, for no longer than `interval` seconds.
        func waitForEnd(within interval: TimeInterval) {
            guard interval > 0 else {
                return
            }
            _ = ended.wait(timeout: .now() + interval)
        }

        /// How many bytes a cancel handler reads from its pipe before closing it, so that a grandchild writing without end cannot hold the close.
        static var finalReadLimit: Int {
            1 << 20
        }

        /// A source that appends what the non-blocking read end at `index` delivers, cancels itself at end of file, and reads what is left before closing the read end once cancelled.
        private func drain(_ index: Int, on queue: DispatchQueue) -> DispatchSourceRead {
            let handle = handles[index]
            let descriptor = handle.fileDescriptor
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
            source.setEventHandler { [self] in
                let read = Self.read(descriptor)
                if let bytes = read.bytes {
                    append(bytes, isError: index == 1)
                    return
                }
                // Nothing to read yet is not the end: the next event brings what this one did not.
                guard read.error != EAGAIN else {
                    return
                }
                // A read that finds the end of the file ends the stream, and so does one that fails.
                reachedEnd()
                sources[index].cancel()
            }
            source.setCancelHandler { [self] in
                var remaining = Self.finalReadLimit
                while remaining > 0, let bytes = Self.read(descriptor, upTo: remaining).bytes {
                    append(bytes, isError: index == 1)
                    remaining -= bytes.count
                }
                try? handle.close()
                released.signal()
            }
            return source
        }

        /// One read of up to 64 KiB, and no more than `limit`, from a non-blocking descriptor, retried when a signal interrupts it: the bytes read, or `nil` with the `errno` of a read that found none, which is zero at end of file.
        private static func read(_ descriptor: Int32, upTo limit: Int = 65536) -> (bytes: Data?, error: Int32) {
            var buffer = [UInt8](repeating: 0, count: min(65536, limit))
            while true {
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count > 0 {
                    return (Data(buffer[..<count]), 0)
                }
                let error = count == 0 ? 0 : errno
                if error != EINTR {
                    return (nil, error)
                }
            }
        }

        /// How many bytes of standard output the readiness search has looked at, counting the overlap it re-reads each time.
        var scannedBytes: Int {
            lock.lock()
            defer { lock.unlock() }
            return scanned
        }

        /// The bytes of standard output a search reads once it has been through `searchedThrough`: the new ones up to `end`, and the marker's length less one before them that a split marker would start in, and no earlier.
        static func searchWindow(searchedThrough: Int, end: Int, markerLength: Int) -> Range<Int> {
            max(0, searchedThrough - (markerLength - 1)) ..< end
        }

        /// Adds what arrived to its stream and, for standard output, looks for the readiness marker in the new bytes and the few before them that a split marker would start in.
        func append(_ data: Data, isError: Bool) {
            lock.lock()
            if isError {
                standardError.append(data)
            } else {
                standardOutput.append(data)
            }
            var ready = false
            if !isError, !readinessSignalled, let marker = readiness?.marker {
                let window = Self.searchWindow(searchedThrough: searchedThrough, end: standardOutput.endIndex, markerLength: marker.count)
                scanned += window.count
                ready = standardOutput[window].range(of: marker) != nil
                searchedThrough = standardOutput.endIndex
            }
            readinessSignalled = readinessSignalled || ready
            lock.unlock()
            if ready {
                readiness?.seen.signal()
            }
        }

        private func reachedEnd() {
            lock.lock()
            open -= 1
            let last = open == 0
            lock.unlock()
            if last {
                ended.signal()
            }
        }

        /// Stops reading whatever is still holding the write end open, and waits for both read ends to be closed.
        ///
        /// A handler already running finishes before its source's cancel handler runs, so a read end is never closed under a read of it, and each cancel handler takes what is left in its pipe before it closes the read end. The wait is bounded like every other on the spawn's way out: a cancel handler that has not run when it expires still closes its read end, only after the call has returned.
        private func stop() {
            for source in sources {
                source.cancel()
            }
            let deadline = DispatchTime.now() + Subprocess.terminationGrace
            for _ in sources {
                _ = released.wait(timeout: deadline)
            }
        }
    }
}

extension Subprocess.SpawnStreams {
    /// What a spawn that waits for its child to say it is set up watches for, and the signal raised when it shows.
    struct Readiness {
        let marker: Data
        let seen = DispatchSemaphore(value: 0)
    }
}
