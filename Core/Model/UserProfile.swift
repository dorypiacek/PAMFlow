//
//  UserProfile.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation

/// Local user identity displayed in the top bar.
public struct UserProfile: Codable, Equatable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}
