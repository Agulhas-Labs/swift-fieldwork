// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The read, merge and write steps an agent's settings-style file goes through, whichever agent it configures.
public extension SettingsFile {
    /// The bytes at `url`, `nil` when nothing is there; a file that cannot be read, or a link that leads nowhere, is refused, since reading it as empty would replace it.
    ///
    /// `agent` is the harness a refusal names and `flag` the option that points the install at another directory.
    static func read(_ url: URL, agent: String, flag: String) throws -> Data? {
        do {
            _ = try SettingsFile.target(of: url)
        } catch let unresolved as SettingsFile.Unresolved {
            throw Refused(path: url.path, reason: "is \(unresolved.reason) — repair the link, or point \(flag) at another directory", agent: agent)
        }
        guard PathKind.of(url) != .absent else { return nil }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw Refused(path: url.path, reason: "could not be read: \(error.localizedDescription)", agent: agent)
        }
    }

    /// Runs one file's merge, naming the file's path in a refusal of its shape.
    static func merge<Result>(_ url: URL, agent: String, _ body: () throws -> Result) throws -> Result {
        do {
            return try body()
        } catch let unmergeable as CursorConfigJSON.Unmergeable {
            throw Refused(path: url.path, reason: "cannot be merged: \(unmergeable.description)", agent: agent)
        }
    }

    /// Rewrites `url` with `data` when `changed`, keeping `original` beside it under `tool`'s name, and records the file and any backup note in `outcome`.
    static func write(_ outcome: inout InstallOutcome, _ url: URL, _ data: Data, original: Data?, if changed: Bool, tool: FieldworkTool) throws {
        guard changed else { return }
        if let backupNote = try SettingsFile.rewrite(url, with: data, original: original, tool: tool) {
            outcome.notes.append(backupNote)
        }
        outcome.written.append(SettingsFile.named(url))
    }

    /// A harness's file that is there and could not be read, leads nowhere, or is not a shape a merge can build on, so nothing was written.
    struct Refused: Error, CustomStringConvertible, Sendable {
        public let path: String
        public let reason: String
        /// The harness the file configures, as the refusal's first word.
        public let agent: String

        public init(path: String, reason: String, agent: String) {
            self.path = path
            self.reason = reason
            self.agent = agent
        }

        public var description: String {
            "\(agent): nothing written — \(path) \(reason)"
        }
    }
}
