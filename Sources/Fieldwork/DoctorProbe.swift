// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Runs what an agent would run — a registered hook command, the registered server, the registered binary — inside a scratch directory, with every per-user path pointed into it, so a check writes nothing a person reads.
public final class DoctorProbe: @unchecked Sendable {
    /// The tool being checked: its name is the scratch directory's and the MCP client's.
    public let tool: FieldworkTool
    /// The tool's own version, which is the MCP client's version and what a registered binary's is compared with.
    public let runningVersion: String
    /// The scratch directory, removed by ``close()``, or when the probe is released.
    let scratch: URL
    /// The directory every child runs in and every payload names as its `cwd`.
    public let workspace: URL
    private let environment: [String: String]
    private let limit: TimeInterval
    private let launcher: Launcher

    /// A probe for `machine`'s environment, with every child stopped after `limit` seconds.
    ///
    /// - Parameters:
    ///   - scrubbing: Environment variables whose names start with any of these are dropped: every switch the tool reads, so none can make a hook pass by staying silent.
    ///   - pointing: The variables the tool reads for its own files, given the scratch home directory, set after the scrub.
    ///   - launcher: Starts a child; ``launch(_:arguments:input:environment:within:)`` unless the consumer has its own.
    public init(
        tool: FieldworkTool,
        version: String,
        environment machine: [String: String],
        scrubbing prefixes: [String] = [],
        pointing: (_ home: URL) -> [String: String] = { _ in [:] },
        limit: TimeInterval = 20,
        launcher: @escaping Launcher = { binary, arguments, input, environment, limit in
            DoctorProbe.launch(binary, arguments: arguments, input: input, environment: environment, within: limit)
        }
    ) throws {
        self.tool = tool
        runningVersion = version
        scratch = FileManager.default.temporaryDirectory.appendingPathComponent("\(tool.name)-doctor-\(UUID().uuidString)", isDirectory: true)
        workspace = scratch.appendingPathComponent("workspace", isDirectory: true)
        let home = scratch.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        var environment = machine.filter { entry in !prefixes.contains { entry.key.hasPrefix($0) } }
        for key in ["CLAUDE_CODE_SESSION_ID", "CLAUDECODE"] {
            environment[key] = nil
        }
        environment["HOME"] = home.path
        environment["CFFIXED_USER_HOME"] = home.path
        environment.merge(pointing(home)) { _, set in set }
        self.environment = environment
        self.limit = limit
        self.launcher = launcher
    }

    /// Removes the scratch directory; a second call, and the release of a closed probe, do nothing more.
    public func close() {
        try? FileManager.default.removeItem(at: scratch)
    }

    deinit {
        close()
    }

    /// `command` run the way an agent runs a hook, through `sh -c`, in the workspace, with `input` on its input: its exit status and what it printed, or `nil` where it could not be started or outran the limit.
    public func run(shell command: String, input: Data = Data()) -> (status: Int32, output: Data)? {
        launcher(
            URL(fileURLWithPath: "/bin/sh"),
            ["-c", "cd \(ShellWord.quoted(workspace.path)) && \(command)"],
            input,
            environment,
            limit
        )
    }

    /// `binary --version`'s first line, or why there is none.
    public func version(of binary: String) -> Result<String, Refusal> {
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            return .failure(Refusal("\(binary) is not there, or is not executable"))
        }
        guard let run = run(shell: "\(ShellWord.quoted(binary)) --version"), run.status == 0 else {
            return .failure(Refusal("\(binary) --version did not exit 0"))
        }
        let text = String(bytes: run.output, encoding: .utf8) ?? ""
        return .success(text.split(separator: "\n").first.map(String.init) ?? "")
    }

    /// The server `command` starts, asked to initialize and list its tools over stdio: the tools it listed, or why it did not.
    public func listedTools(command: String) -> Result<[String], Refusal> {
        let requests: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": [
                "protocolVersion": "2025-06-18", "capabilities": [String: Any](), "clientInfo": ["name": "\(tool.name)-doctor", "version": runningVersion],
            ]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
        ]
        var input = Data()
        for request in requests {
            input += (try? JSONSerialization.data(withJSONObject: request)) ?? Data()
            input += Data("\n".utf8)
        }
        guard let run = run(shell: command, input: input) else {
            return .failure(Refusal("did not start, or did not answer within \(Int(limit))s"))
        }
        let replies = (String(bytes: run.output, encoding: .utf8) ?? "").split(separator: "\n").map { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
        guard !replies.isEmpty else {
            return .failure(Refusal("answered nothing (exit \(run.status))"))
        }
        guard replies.allSatisfy({ $0?["jsonrpc"] as? String == "2.0" }) else {
            return .failure(Refusal("printed something other than JSON-RPC on stdout"))
        }
        let listing = replies.compactMap(\.self).first { $0["id"] as? Int == 2 }
        let tools = ((listing?["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        guard let tools else {
            return .failure(Refusal("answered no tools/list"))
        }
        return .success(tools)
    }
}

public extension DoctorProbe {
    /// Why a probe has no answer, as the check's line says it.
    struct Refusal: Error, Equatable, Sendable {
        public let reason: String

        public init(_ reason: String) {
            self.reason = reason
        }
    }
}
