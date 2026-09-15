//
//  ModuleScreenRoute.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Core
import Foundation

/// A stable route to a screen owned by a feature module workflow.
///
/// The host app uses this value to display whichever screen the active module
/// exposes. Screen identifiers remain opaque outside the module that created
/// them, keeping top-level navigation independent from workflow internals.
public struct ModuleScreenRoute: Hashable, Sendable {
    public let moduleID: ModuleID
    public let screenID: String
    public let projectID: UUID
    public let startAtLastReviewed: Bool

    public init(moduleID: ModuleID, screenID: String, projectID: UUID, startAtLastReviewed: Bool = false) {
        self.moduleID = moduleID
        self.screenID = screenID
        self.projectID = projectID
        self.startAtLastReviewed = startAtLastReviewed
    }
}
