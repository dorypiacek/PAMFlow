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
public struct ProjectWorkflowStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = Self.normalizedRawValue(rawValue)
    }

    public init(_ rawValue: String) {
        self.rawValue = Self.normalizedRawValue(rawValue)
    }

    public static let created = ProjectWorkflowStatus("created")
    public static let inProgress = ProjectWorkflowStatus("in_progress")
    public static let scanInProgress = ProjectWorkflowStatus("scan_in_progress")
    public static let scanCompleted = ProjectWorkflowStatus("scan_completed")
    public static let manualAuditInProgress = ProjectWorkflowStatus("manual_audit_in_progress")
    public static let manualAuditCompleted = ProjectWorkflowStatus("manual_audit_completed")
    public static let detectionReviewInProgress = ProjectWorkflowStatus("detection_review_in_progress")
    public static let completed = ProjectWorkflowStatus("completed")
}

public extension ProjectWorkflowStatus {
    /// Returns a readable title for generic workflow states known to Core.
    var genericDisplayTitle: String {
        switch self {
        case .created:
            "Created"
        case .inProgress:
            "In progress"
        case .scanInProgress:
            "Scan in progress"
        case .scanCompleted:
            "Scan completed"
        case .manualAuditInProgress:
            "Manual audit in progress"
        case .manualAuditCompleted:
            "Manual audit completed"
        case .detectionReviewInProgress:
            "Detection review in progress"
        case .completed:
            "Completed"
        default:
            rawValue
                .split(separator: "_")
                .map { $0.capitalized }
                .joined(separator: " ")
        }
    }

    /// Normalizes legacy workflow tokens produced before workflow state became
    /// an opaque module-owned value.
    static func normalizedRawValue(_ rawValue: String) -> String {
        let key = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber
            }

        switch key {
        case "created", "projectcreated":
            return "created"
        case "inprogress":
            return "in_progress"
        case "scaninprogress":
            return "scan_in_progress"
        case "scancompleted":
            return "scan_completed"
        case "manualauditinprogress":
            return "manual_audit_in_progress"
        case "manualauditcompleted", "allaudited", "allaudioreviewed":
            return "manual_audit_completed"
        case "detectionreviewinprogress":
            return "detection_review_in_progress"
        case "completed", "projectcompleted":
            return "completed"
        default:
            return rawValue
        }
    }
}
