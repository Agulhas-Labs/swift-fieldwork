// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The agent rule half of the Claude Code install: copies the rule file that ships beside the binary to the rule path, as the tool's `install.sh` does.
///
/// A symlink at the rule path is left alone, since it means the rule is a checkout's own file; a rule that differs is kept under the tool's backup name before it is replaced.
public struct ClaudeRuleInstall: Equatable, Sendable {
    /// The tool the rule belongs to.
    public let tool: FieldworkTool
    /// The file name the rule ships under, beside the binary and in the share directory.
    public let shippedFileName: String
    /// The directory under `share` that holds the shipped rule where the binary is a package manager's link.
    public let shareDirectory: String
    /// What the rule loads on, as the install line says it: a glob.
    public let loadsOn: String

    public init(tool: FieldworkTool, shippedFileName: String, shareDirectory: String? = nil, loadsOn: String) {
        self.tool = tool
        self.shippedFileName = shippedFileName
        self.shareDirectory = shareDirectory ?? tool.name
        self.loadsOn = loadsOn
    }

    /// The rule that ships with the binary at `binary`: beside the file its links lead to (the release bundle), else in `../share/<shareDirectory>` from there (Homebrew's `pkgshare`), else `nil`.
    public func source(forBinary binary: String) -> URL? {
        let directory = URL(fileURLWithPath: binary).resolvingSymlinksInPath().deletingLastPathComponent()
        let candidates = [
            directory.appendingPathComponent(shippedFileName),
            directory.deletingLastPathComponent().appendingPathComponent("share/\(shareDirectory)/\(shippedFileName)"),
        ]
        return candidates.first { PathKind.of($0.resolvingSymlinksInPath()) == .file }
    }

    /// Reads what an install of `source` at `destination` would do; writes nothing.
    public func plan(source: URL?, destination: URL) -> Plan {
        guard let source else { return .noSource }
        return switch PathKind.of(destination) {
        case .absent:
            .copy
        case let .symlink(target):
            .symlink(target ?? "an unreadable target")
        case .file:
            (try? Data(contentsOf: destination)) == (try? Data(contentsOf: source)) ? .identical : .replace
        case .directory, .other:
            .refused
        }
    }

    /// Why nothing is done where no rule ships beside the binary, for a rule at the destination that is already there (`exists`) or not: `install.sh` writes the rule, and the tool's `install` from Homebrew or npm copies the one they ship, so a rule installed that way is left as it is.
    public func noSourceReason(exists: Bool) -> String {
        let installer = "(install.sh writes it; `\(tool.name) install` from Homebrew or npm copies the \(shippedFileName) they ship)"
        return exists ? "no \(shippedFileName) ships beside this binary to refresh it from \(installer)" : "no \(shippedFileName) ships with this binary \(installer)"
    }

    /// Copies `source` to `destination` as ``plan(source:destination:)`` says, keeping a differing rule beside it first.
    public func install(source: URL?, destination: URL) throws -> InstallOutcome {
        var outcome = InstallOutcome()
        let path = destination.path
        switch plan(source: source, destination: destination) {
        case .noSource:
            let exists = PathKind.of(destination) != .absent
            outcome.notes.append("rule: \(exists ? "left as installed" : "skipped") — \(noSourceReason(exists: exists))")
        case .identical:
            outcome.lines.append("rule: already installed — \(path)")
        case let .symlink(target):
            outcome.lines.append("rule: \(path) is a symlink to \(target) — left as is")
        case .refused:
            outcome.failures.append("rule: not written — \(path) is not a plain file")
        case .copy, .replace:
            guard let source else { return outcome }
            let data = try Data(contentsOf: source)
            let original = try? Data(contentsOf: destination)
            if let backupNote = SettingsBackupFile.write(original, beside: destination, tool: tool) {
                outcome.failures.append("rule: not replaced — \(backupNote)")
                return outcome
            }
            do {
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
            } catch {
                outcome.failures.append("rule: not written — \(path): \(error.localizedDescription)")
                return outcome
            }
            let kept = original == nil ? "" : " (the previous one kept as \(SettingsBackupFile.url(beside: destination, tool: tool).path))"
            outcome.lines.append("rule: installed \(path) (loads on \(loadsOn))\(kept)")
            outcome.written.append(path)
        }
        return outcome
    }

    /// Deletes the rule at `destination` that the install copied in, or leaves a symlink where it is, as the install does: a link means the rule is a checkout's own file, which the install never wrote.
    ///
    /// Only the file at `destination` is touched, so another tool's rule beside it stays; nothing is said where there is nothing there.
    public func uninstall(destination: URL) -> InstallOutcome {
        var outcome = InstallOutcome()
        let path = destination.path
        switch PathKind.of(destination) {
        case .absent:
            break
        case let .symlink(target):
            outcome.lines.append("rule: \(path) is a symlink to \(target ?? "an unreadable target") — left as is")
        case .directory, .other:
            outcome.failures.append("rule: not removed — \(path) is not a plain file")
        case .file:
            do {
                try FileManager.default.removeItem(at: destination)
            } catch {
                outcome.failures.append("rule: not removed — \(path): \(error.localizedDescription)")
                return outcome
            }
            outcome.lines.append("rule: removed \(path)")
            outcome.written.append(path)
        }
        return outcome
    }
}

public extension ClaudeRuleInstall {
    /// What an install would do at the rule path.
    enum Plan: Equatable, Sendable {
        /// No rule ships with this binary, so there is nothing to copy.
        case noSource
        /// Nothing is at the rule path.
        case copy
        /// The rule path already holds these bytes.
        case identical
        /// The rule path is a symlink, to this target.
        case symlink(String)
        /// The rule path holds something else, which is kept beside it before it is replaced.
        case replace
        /// The rule path is not a plain file or a symlink.
        case refused
    }
}
