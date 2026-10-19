// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Fieldwork
import Foundation
import Testing

/// Values a consumer builds for itself outside the library: this file imports `Fieldwork` without `@testable`, so each one here is made through public API alone, as a tool's own Codex file and refusal are.
struct ConsumerConstructionTests {
    @Test
    func aHooksFileChangeIsBuiltFromItsFields() {
        let change = CursorHooksFile.Change(data: Data("{}".utf8), changed: true, replaced: ["/old/bin/gizmo hook"], removed: [])

        #expect(change.data == Data("{}".utf8))
        #expect(change.changed)
        #expect(change.replaced == ["/old/bin/gizmo hook"])
        #expect(change.removed.isEmpty)
    }

    @Test
    func aRefusalIsBuiltForAnotherAgentAndSaysItsName() {
        let refused = SettingsFile.Refused(path: "/home/gizmo/.codex/config.toml", reason: "is a directory", agent: "codex")

        #expect(refused.description == "codex: nothing written — /home/gizmo/.codex/config.toml is a directory")
    }

    @Test
    func theRuleNoteNamesTheInstallCommandTheToolGivesIt() {
        let tool = FieldworkTool(name: "gizmo")
        let named = ClaudeRuleInstall(tool: tool, shippedFileName: "Gizmo.md", loadsOn: "**/*.swift", installCommand: "gizmo install-hook")
        let unnamed = ClaudeRuleInstall(tool: tool, shippedFileName: "Gizmo.md", loadsOn: "**/*.swift")

        #expect(named.noSourceReason(exists: false) == "no Gizmo.md ships with this binary (install.sh writes it; `gizmo install-hook` from Homebrew or npm copies the Gizmo.md they ship)")
        #expect(unnamed.noSourceReason(exists: true).contains("`gizmo install` from Homebrew"))
    }

    @Test
    func aFailedRunSaysWhyThroughPublicAPI() {
        let output = Subprocess.Output(succeeded: false, standardOutput: "", standardError: "Error: failed to load configuration\nCaused by:\nlogin revoked\n")

        #expect(output.failureReason == "Error: failed to load configuration: login revoked")
    }
}
