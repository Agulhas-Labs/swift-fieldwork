// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork

/// The hooks of a made-up tool, `gizmo`, for the tests of ``HookRegistration``: the events a consumer would pass as values.
enum GizmoHooks {
    static let tool = FieldworkTool(name: "gizmo", hookSubcommands: ["session-start", "pre-tool-use", "post-tool-use", "stop"])

    static let sessionStart = HookRegistration.Event(
        name: "SessionStart",
        subcommand: "session-start",
        matchers: ["startup", "resume", "clear", "compact"],
        timeout: 5
    )
    static let subagentStart = HookRegistration.Event(name: "SubagentStart", subcommand: "session-start", matchers: [], timeout: 5)
    static let preToolUse = HookRegistration.Event(
        name: "PreToolUse",
        subcommand: "pre-tool-use",
        matchers: ["Bash|Read|Grep|Glob|mcp__gizmo__.*|Write|Edit|MultiEdit"],
        timeout: 5
    )
    static let postToolUse = HookRegistration.Event(
        name: "PostToolUse",
        subcommand: "post-tool-use",
        matchers: ["Write|Edit|MultiEdit|Grep|Bash"],
        timeout: 3
    )
    static let stop = HookRegistration.Event(name: "Stop", subcommand: "stop", matchers: [], timeout: 5)
    static let subagentStop = HookRegistration.Event(name: "SubagentStop", subcommand: "stop", matchers: [], timeout: 5)

    static let events = [sessionStart, subagentStart, preToolUse, postToolUse, stop, subagentStop]

    static let registration = HookRegistration(tool: tool, events: events)
}
