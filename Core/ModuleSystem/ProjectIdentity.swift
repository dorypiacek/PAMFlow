//
//  ProjectIdentity.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Lightweight project identity passed across module boundaries.
struct ProjectIdentity: Hashable, Sendable {
    let id: UUID
    let moduleID: ModuleID
    let name: String

    init(id: UUID, moduleID: ModuleID, name: String) {
        self.id = id
        self.moduleID = moduleID
        self.name = name
    }
}

extension ProjectIdentity {
    init(project: Project) {
        self.init(
            id: project.id,
            moduleID: ModuleID(rawValue: project.moduleID),
            name: project.name
        )
    }
}
