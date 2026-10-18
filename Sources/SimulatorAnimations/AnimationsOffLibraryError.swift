// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Why the animations-off library could not be made.
public enum AnimationsOffLibraryError: Error, Equatable, Sendable {
    /// The environment variable name is not upper-case letters, digits and underscores, so it is not spliced into source.
    case invalidEnvironmentVariable(String)
    /// The library could not be built, with the reason: the compiler's first error line, or what could not be created or written.
    case notBuilt(String)
}
