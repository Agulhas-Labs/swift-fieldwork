// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SimulatorProfiling

let signalSources = ProfileCommand.installSignalCleanup()
let status = ProfileCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
withExtendedLifetime(signalSources) {
    exit(status)
}
