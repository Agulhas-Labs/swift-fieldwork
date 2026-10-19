// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

/// What a Cursor hook install or uninstall did: the merge's ``InstallOutcome``, and every line to print for it.
public struct CursorHookInstallResult: Equatable, Sendable {
    /// The merge's own outcome: its `lines` are the registration lines alone, so a consumer printing `printed` does not print `written` or `notes` again.
    public var outcome: InstallOutcome
    /// Everything to print, in order.
    public var printed: [String]

    public init(outcome: InstallOutcome, printed: [String]) {
        self.outcome = outcome
        self.printed = printed
    }
}
