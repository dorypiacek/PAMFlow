//
//  ManualAuditDecision.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation
import SwiftData

/// Human audit decision for one scanned input file.
public enum ManualAuditDecisionValue: String, CaseIterable, Codable, Hashable {
    case valid
    case unsure
    case invalid

    public var title: String {
        switch self {
        case .valid:
            "Valid"
        case .unsure:
            "Unsure"
        case .invalid:
            "Invalid"
        }
    }
}

/// SwiftData record storing the user's manual audit decision and optional species.
@Model
public final class ManualAuditDecision {
    @Attribute(.unique) public var id: String
    public var projectID: UUID
    public var fileRelativePath: String
    var decisionRaw: String
    public var notes: String
    public var speciesFamily: String?
    public var speciesGenus: String?
    public var speciesName: String?
    public var speciesFullName: String?
    public var speciesSelectionsJSON: String?
    public var isRemovedFromExport: Bool?
    public var userMaxN: Int?
    public var createdAt: Date
    public var updatedAt: Date?

    public init(
        projectID: UUID,
        fileRelativePath: String,
        decision: ManualAuditDecisionValue,
        notes: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = Self.makeID(projectID: projectID, fileRelativePath: fileRelativePath)
        self.projectID = projectID
        self.fileRelativePath = fileRelativePath
        self.decisionRaw = decision.rawValue
        self.notes = notes
        self.speciesFamily = nil
        self.speciesGenus = nil
        self.speciesName = nil
        self.speciesFullName = nil
        self.speciesSelectionsJSON = nil
        self.isRemovedFromExport = nil
        self.userMaxN = nil
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension ManualAuditDecision {
    var decision: ManualAuditDecisionValue {
        get {
            ManualAuditDecisionValue(rawValue: decisionRaw) ?? .unsure
        }
        set {
            decisionRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    static func makeID(projectID: UUID, fileRelativePath: String) -> String {
        "\(projectID.uuidString)::\(fileRelativePath)"
    }
}

/// Configuration consumed by the shared audit shell.
public struct ManualAuditConfiguration: Hashable, Sendable {
    public let title: String
    public let emptyStateTitle: String
    public let decisionOptions: [AuditDecisionOption]

    public init(title: String, emptyStateTitle: String, decisionOptions: [AuditDecisionOption]) {
        self.title = title
        self.emptyStateTitle = emptyStateTitle
        self.decisionOptions = decisionOptions
    }
}

/// Generic audit decision exposed by a module.
public struct AuditDecisionOption: Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}
