//
//  ProjectIdentity.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Lightweight project identity passed across module boundaries.
public struct ProjectIdentity: Hashable, Sendable {
    public let id: UUID
    public let moduleID: ModuleID
    public let name: String

    public init(id: UUID, moduleID: ModuleID, name: String) {
        self.id = id
        self.moduleID = moduleID
        self.name = name
    }
}

public extension ProjectIdentity {
    init(project: Project) {
        self.init(
            id: project.id,
            moduleID: ModuleID(rawValue: project.moduleID),
            name: project.name
        )
    }
}
