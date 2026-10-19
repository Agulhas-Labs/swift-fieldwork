// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The Cursor half of a tool's `install-hook` and `uninstall-hook`: runs the merge in ``CursorInstall`` and returns what it did and every line the tool prints, in the order it prints them.
///
/// The consumer passes what it says on every install: ``unsupported`` is what it does not carry over to Cursor, one line each, and ``experimental`` a closing note on how far the support has been verified.
public struct CursorHookInstaller: Equatable, Sendable {
    /// The merge this runs.
    public let cursor: CursorInstall
    /// What the install output names as not carried over to Cursor, one line each.
    public let unsupported: [String]
    /// Said on every install after the unsupported lines, or `nil` for nothing.
    public let experimental: String?

    public init(cursor: CursorInstall, unsupported: [String] = [], experimental: String? = nil) {
        self.cursor = cursor
        self.unsupported = unsupported
        self.experimental = experimental
    }

    /// The one manual step after an install that changed something.
    public static var restart: String {
        "restart Cursor to load the registration"
    }

    /// The one manual step after an uninstall that changed something.
    public static var restartAfterRemoval: String {
        "restart Cursor to unload the registration"
    }

    /// Registers the server and the hooks in `directory` for `binary`, an absolute path.
    ///
    /// The result's `printed` is everything to print, in order: the merge's lines, each file written (indented), the notes, the restart step when something changed, then the unsupported lines and the experimental note. Its `outcome` is the merge's own, for a step report.
    @discardableResult
    public func install(directory: URL, binary: String) throws -> CursorHookInstallResult {
        let outcome = try cursor.install(directory: directory, binary: binary, binaryWord: ShellWord.quoted(binary))
        var printed = Self.printable(outcome)
        if outcome.changed {
            printed.append(Self.restart)
        }
        printed += unsupported
        if let experimental {
            printed.append(experimental)
        }
        return CursorHookInstallResult(outcome: outcome, printed: printed)
    }

    /// Takes out what the install wrote in `directory`; the result's `printed` is everything to print, in order.
    @discardableResult
    public func uninstall(directory: URL) throws -> CursorHookInstallResult {
        let outcome = try cursor.uninstall(directory: directory)
        var printed: [String] = []
        if outcome.lines.isEmpty {
            printed.append("cursor: nothing registered in \(directory.path)")
        }
        printed += Self.printable(outcome)
        if outcome.changed {
            printed.append(Self.restartAfterRemoval)
        }
        return CursorHookInstallResult(outcome: outcome, printed: printed)
    }

    private static func printable(_ outcome: InstallOutcome) -> [String] {
        outcome.lines + outcome.written.map { "      \($0)" } + outcome.notes
    }
}
