//
//  ModuleID.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Foundation

/// Stable identifier for a feature module.
///
/// Core stores module IDs as opaque values. Feature modules own the meaning of
/// their IDs and any workflow state associated with them.
public struct ModuleID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension ModuleID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}
