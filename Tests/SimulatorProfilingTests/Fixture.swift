// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A file or directory under this test target's `Fixtures`.
func fixture(_ path: String) -> URL {
    (Bundle.module.resourceURL ?? Bundle.module.bundleURL).appendingPathComponent("Fixtures").appendingPathComponent(path)
}
