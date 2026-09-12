//
//  ProjectWorkflowState.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Foundation

/// Opaque workflow state owned by a feature module.
///
/// Core persists this value but does not interpret `stateID` or `payload`.
struct ProjectWorkflowState: Codable, Hashable, Sendable {
    let moduleID: ModuleID
    let stateID: String
    let version: Int
    let updatedAt: Date
    let display: WorkflowDisplayState?
    let payload: Data?

    init(
        moduleID: ModuleID,
        stateID: String,
        version: Int = 1,
        updatedAt: Date = .now,
        display: WorkflowDisplayState? = nil,
        payload: Data? = nil
    ) {
        self.moduleID = moduleID
        self.stateID = stateID
        self.version = version
        self.updatedAt = updatedAt
        self.display = display
        self.payload = payload
    }
}

/// Module-written project list / read-only display snapshot.
struct WorkflowDisplayState: Codable, Hashable, Sendable {
    let title: String
    let subtitle: String?
    let primaryActionTitle: String?
    let progress: Double?

    init(
        title: String,
        subtitle: String? = nil,
        primaryActionTitle: String? = nil,
        progress: Double? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.primaryActionTitle = primaryActionTitle
        self.progress = progress
    }
}
