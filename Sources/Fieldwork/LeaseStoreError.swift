// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Why a lease could not be taken, used or released.
public enum LeaseStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The device carries a live lease the caller did not present.
    case held(udid: String, holderPID: Int32, expiresAt: Date)
    /// A lease file that does not decode — never reclaimed, since what cannot be read cannot be judged free.
    case unreadable(path: String)
    /// No lease carries the token presented.
    case noSuchLease
    /// The lease on the device ran out before it was used.
    case expired(udid: String, expiresAt: Date)
    /// A lease whose holder has exited: reclaimable by anyone, so renewing it would keep nobody off the device.
    case holderExited(udid: String, holderPID: Int32)
    /// A device a lease cloned whose lease has lapsed: it is released — the clone deleted — and never leased again.
    case awaitingDeletion(udid: String)
    /// The lease directory or a lease file could not be written.
    case storeFailed(path: String, reason: String)

    public var description: String {
        switch self {
        case let .held(udid, pid, expiresAt):
            "\(udid) is leased by pid \(pid) until \(Self.time(expiresAt))"
        case let .unreadable(path):
            "the lease at \(path) cannot be read, so the device is treated as held — remove the file if no walk holds it"
        case .noSuchLease:
            "no lease carries that token — it was released, or reclaimed after it expired"
        case let .expired(udid, expiresAt):
            "the lease on \(udid) expired at \(Self.time(expiresAt))"
        case let .holderExited(udid, pid):
            "the lease on \(udid) lived as long as pid \(pid), which has exited, so any session may reclaim it and renewing it would keep nobody off the device"
        case let .awaitingDeletion(udid):
            "\(udid) is a clone a lease made, and that lease has lapsed or is being released, so the device is deleted rather than leased again"
        case let .storeFailed(path, reason):
            "the lease store at \(path) could not be written: \(reason)"
        }
    }

    /// A lease's expiry as its refusal prints it: the subject of the line, not its provenance.
    public static func time(_ date: Date) -> String {
        date.formatted(.iso8601)
    }
}
