// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// More services needed switching on than a profile can usefully keep.
public struct BisectionError: Error, CustomStringConvertible, Equatable {
    public let maxKept: Int

    public var description: String {
        "more than \(maxKept) candidates fail the health check when switched off; the candidates are not safe to switch off as a set"
    }
}

/// Finds the candidates a device needs.
public enum Bisection {
    /// The candidates to keep on, sorted: those without which `fails` reports a failure.
    ///
    /// While the remaining candidates, all switched off, fail, the smallest prefix that fails gives away the one at its end, which is kept and removed. A candidate that fails only together with another is kept by the later of the two.
    public static func kept(candidates: [String], maxKept: Int = 12, fails: ([String]) throws -> Bool) throws -> [String] {
        var remembered: [[String]: Bool] = [:]
        func failing(_ set: [String]) throws -> Bool {
            if set.isEmpty {
                return false
            }
            if let known = remembered[set] {
                return known
            }
            let result = try fails(set)
            remembered[set] = result
            return result
        }
        var remaining = Array(Set(candidates)).sorted()
        var kept: [String] = []
        while try failing(remaining) {
            var low = 1
            var high = remaining.count
            while low < high {
                let middle = (low + high) / 2
                if try failing(Array(remaining[0 ..< middle])) {
                    high = middle
                } else {
                    low = middle + 1
                }
            }
            guard kept.count < maxKept else { throw BisectionError(maxKept: maxKept) }
            kept.append(remaining.remove(at: low - 1))
        }
        return kept.sorted()
    }
}
