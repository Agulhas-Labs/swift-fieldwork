// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Why a simulator-services operation failed.
public enum SimulatorServicesError: Error, Equatable {
    /// The text is not a UUID, so no path is built from it.
    case invalidUDID(String)
    /// A command ran and failed, with what it printed on standard error.
    case commandFailed(command: String, standardError: String)
    /// A profile written in a newer format than this library reads.
    case unsupportedSchema(found: Int, supported: Int)
}
