// swift-tools-version: 6.2
// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import PackageDescription

/// No warnings-as-errors or unsafeFlags here: in a dependency's manifest they break consumers' builds on a new compiler warning, so the checks pass the strict build on the command line (`-Xswiftc -warnings-as-errors`).
let package = Package(
    name: "swift-fieldwork",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "Fieldwork", targets: ["Fieldwork"]),
        .library(name: "SimulatorServices", targets: ["SimulatorServices"]),
        .library(name: "SimulatorAnimations", targets: ["SimulatorAnimations"]),
        .executable(name: "simulator-profile", targets: ["SimulatorProfile"]),
    ],
    targets: [
        .target(name: "Fieldwork"),
        .target(name: "SimulatorServices", dependencies: ["Fieldwork"]),
        .target(name: "SimulatorAnimations", dependencies: ["Fieldwork"]),
        .target(name: "SimulatorProfiling", dependencies: ["SimulatorServices", "Fieldwork"]),
        .executableTarget(name: "SimulatorProfile", dependencies: ["SimulatorProfiling"]),
        .testTarget(
            name: "SimulatorProfilingTests",
            dependencies: ["SimulatorProfiling"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "SimulatorAnimationsTests", dependencies: ["SimulatorAnimations"]),
        .testTarget(
            name: "SimulatorServicesTests",
            dependencies: ["SimulatorServices"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "FieldworkTests",
            dependencies: ["Fieldwork"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
