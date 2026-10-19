// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

/// This process's handling of `SIGINT` and `SIGQUIT` while a member runs: ignored from the first launch that starts until the last one running ends, then put back as it was.
///
/// Counted so that two launches that overlap cannot leave the process ignoring Ctrl-C: the second would otherwise save the ignored handling the first set, and put it back last.
final class TerminalSignals: @unchecked Sendable {
    private let lock = NSLock()
    private var running = 0
    private var savedInterrupt = sigaction()
    private var savedQuit = sigaction()

    /// Only ``terminalSignals`` makes one: a second instance would save the handling the first had set to ignored, and put that back last.
    fileprivate init() {}

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

/// The one handling of the terminal signals this process has, since the signal dispositions are the process's.
let terminalSignals = TerminalSignals()
