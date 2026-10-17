// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The tool this library is working for: the one place a consumer's identity enters.
public struct FieldworkTool: Equatable, Sendable {
    /// The tool's name: its binary, its MCP server name, and the word every message uses (`<name> install`).
    public let name: String

    /// The subcommands the tool's registered hooks run, which is what ``isMentioned(in:)`` looks for after the program word.
    public let hookSubcommands: [String]

    public init(name: String, hookSubcommands: [String] = []) {
        self.name = name
        self.hookSubcommands = hookSubcommands
    }

    /// The name of the tool's rule file under `<claude>/rules/`.
    public var installedRuleName: String {
        "\(name).md"
    }

    /// The path extension of the backup left beside a settings file the tool rewrites: `bak-<name>`, so `settings.json.bak-<name>`.
    public var backupExtension: String {
        "bak-\(name)"
    }

    /// Whether a registered shell `command` is this tool's binary running `subcommand` and nothing else: its first shell word is a path whose last component is ``name``, followed by exactly that subcommand.
    ///
    /// The first word is read the way a shell reads it, quoting and escapes included, so `"/opt/wrap" "/x/gizmo" stop` is `/opt/wrap` running something and `python3 tools/gizmo stop` is `python3` running a script: a command whose first word is any other program is never this tool's. A path that merely contains the name (`/opt/gizmoworks/x`) is someone else's too, and so is a subcommand with anything after it. A path with a space in it is claimed quoted, or unquoted only as an older install wrote it (see the legacy rule below).
    public func runs(_ command: String, subcommand: String) -> Bool {
        let command = command.trimmingCharacters(in: .whitespaces)
        if let (executable, rest) = firstShellWord(of: command),
           rest.trimmingCharacters(in: .whitespaces) == subcommand,
           (executable as NSString).lastPathComponent == name
        {
            return true
        }
        return namesAnInstalledBinaryUnquoted(command, subcommand: subcommand)
    }

    /// Whether a registered shell `command` runs one of the tool's ``hookSubcommands``: its program word is a path whose last component is ``name``, or the package an `npx` or `bunx` runs, and the word after it is such a subcommand; a command ``runs(_:subcommand:)`` claims for one of them counts too, the unquoted path with a space in it an older install wrote among them.
    ///
    /// Wider than ``runs(_:subcommand:)`` on purpose, for a check that wants any trace: arguments after the subcommand and a wrapper such as `npx -y @scope/gizmo stop` count. The program word is read after any environment assignments, `exec`, `env` and `command`, so a path that merely contains the name (`cd ~/gizmo && make`) and an argument that is the name (`foo --name gizmo`) do not.
    public func isMentioned(in command: String) -> Bool {
        if hookSubcommands.contains(where: { runs(command, subcommand: $0) || hasTheUnquotedShape(command, subcommand: $0) }) {
            return true
        }
        var words: [String] = []
        var rest = command
        while let (word, remainder) = firstShellWord(of: rest.trimmingCharacters(in: .whitespaces)) {
            words.append(word)
            rest = remainder
        }
        let wrappers: Set = ["exec", "env", "command"]
        guard let start = words.firstIndex(where: { !wrappers.contains($0) && !isEnvironmentAssignment($0) }) else { return false }
        var subcommandIndex = start + 1
        switch (words[start] as NSString).lastPathComponent {
        case name:
            break
        case "npx", "bunx":
            while subcommandIndex < words.count, words[subcommandIndex].hasPrefix("-") {
                subcommandIndex += 1
            }
            guard subcommandIndex < words.count else { return false }
            let package = (words[subcommandIndex] as NSString).lastPathComponent
            guard package == name || package.hasPrefix(name + "@") else { return false }
            subcommandIndex += 1
        default:
            return false
        }
        guard subcommandIndex < words.count else { return false }
        return hookSubcommands.contains(words[subcommandIndex])
    }

    private func isEnvironmentAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        let name = word[..<equals]
        return !(name.first?.isNumber ?? true) && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// Whether `command` has the unquoted shape an older install wrote, whether or not its binary is still there.
    ///
    /// No quoting, an absolute path whose last component is ``name``, then the subcommand: a hook whose binary was moved or deleted is the most broken trace of all, so a check for any trace must not need the file.
    private func hasTheUnquotedShape(_ command: String, subcommand: String) -> Bool {
        guard command.hasSuffix(" " + subcommand), !command.contains(where: { "'\"\\".contains($0) }) else { return false }
        let path = command.dropLast(subcommand.count + 1).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") && (path as NSString).lastPathComponent == name
    }

    /// The shape an older install wrote for a binary under a directory with a space in it.
    ///
    /// It had no quoting, so the first word is only part of the path. Claimed only when everything before the subcommand is an absolute path to an existing regular file named ``name``, which `/opt/wrap /x/gizmo` is not.
    private func namesAnInstalledBinaryUnquoted(_ command: String, subcommand: String) -> Bool {
        guard command.hasSuffix(" " + subcommand), !command.contains(where: { "'\"\\".contains($0) }) else { return false }
        let path = command.dropLast(subcommand.count + 1).trimmingCharacters(in: .whitespaces)
        var isDirectory: ObjCBool = false
        return path.hasPrefix("/")
            && (path as NSString).lastPathComponent == name
            && FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    /// The first word of `command` with its quoting removed, and everything after it; `nil` for an empty command or an unterminated quote.
    ///
    /// Read by scalar, not by `Character`: a quote followed by a combining mark is one `Character` but still a quote to a shell.
    private func firstShellWord(of command: String) -> (word: String, rest: String)? {
        let scalars = Array(command.unicodeScalars)
        var word = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count, !Character(scalars[index]).isWhitespace {
            let scalar = scalars[index]
            index += 1
            switch scalar {
            case "'":
                guard let close = scalars[index...].firstIndex(of: "'") else { return nil }
                word.append(contentsOf: scalars[index ..< close])
                index = close + 1
            case "\"":
                var closed = false
                while index < scalars.count, !closed {
                    let inner = scalars[index]
                    index += 1
                    if inner == "\"" {
                        closed = true
                    } else if inner == "\\", index < scalars.count, "\\\"$`".unicodeScalars.contains(scalars[index]) {
                        word.append(scalars[index])
                        index += 1
                    } else {
                        word.append(inner)
                    }
                }
                guard closed else { return nil }
            case "\\":
                guard index < scalars.count else { return nil }
                word.append(scalars[index])
                index += 1
            default:
                word.append(scalar)
            }
        }
        guard !word.isEmpty else { return nil }
        var rest = String.UnicodeScalarView()
        rest.append(contentsOf: scalars[index...])
        return (String(word), String(rest))
    }
}
