//
//  ProjectWorkflowStatus.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation

/// Durable workflow milestone for a project.
///
/// Core treats workflow state as an opaque persisted token. Feature modules own
/// the meaning, display text, and routing behavior for their module-specific
/// states.
struct ProjectWorkflowStatus: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static let created = ProjectWorkflowStatus("created")
    static let inProgress = ProjectWorkflowStatus("in_progress")
    static let scanInProgress = ProjectWorkflowStatus("scan_in_progress")
    static let scanCompleted = ProjectWorkflowStatus("scan_completed")
    static let manualAuditInProgress = ProjectWorkflowStatus("manual_audit_in_progress")
    static let manualAuditCompleted = ProjectWorkflowStatus("manual_audit_completed")
    static let detectionReviewInProgress = ProjectWorkflowStatus("detection_review_in_progress")
    static let completed = ProjectWorkflowStatus("completed")
}
