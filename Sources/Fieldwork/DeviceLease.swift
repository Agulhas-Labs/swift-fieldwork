// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One device's lease, as `<udid>.json` in the lease directory holds it: who holds it, until when, and whether the lease made the device.
///
/// The token is the capability — a walk that presents it may use the device and reboot it — so it is written here and printed once, to the caller that acquired it, and never listed.
public struct DeviceLease: Codable, Equatable, Sendable {
    /// What the holder presents to use the device and to release it.
    public let token: String
    /// The process the lease lives as long as; once it is gone the lease is reclaimable.
    public let holderPID: Int32
    /// When the lease was taken.
    public let createdAt: Date
    /// After this the lease is reclaimable, and a prune releases it.
    public let expiresAt: Date
    /// Whether the lease made the device by cloning another — the only case in which releasing it deletes the device.
    public let createdDevice: Bool
    /// The device it was cloned from, when it was.
    public let clonedFrom: String?
    /// Whether the lease is on a paired physical iPhone; absent in a lease written before the phone could be leased, which is a simulator's.
    public let physicalDevice: Bool?
    /// Whether the device was shut down when the lease was taken on it, so that releasing the lease may shut it down again and leave it as it was found; absent when it was not, or in a lease written before this was recorded, and then the device is left as it is.
    public let foundShutDown: Bool?

    public init(token: String, holderPID: Int32, createdAt: Date, expiresAt: Date, createdDevice: Bool, clonedFrom: String?, physicalDevice: Bool? = nil, foundShutDown: Bool? = nil) {
        self.token = token
        self.holderPID = holderPID
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.createdDevice = createdDevice
        self.clonedFrom = clonedFrom
        self.physicalDevice = physicalDevice
        self.foundShutDown = foundShutDown
    }
}
