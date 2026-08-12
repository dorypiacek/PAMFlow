//
//  ManualAuditDecision.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation
import SwiftData

/// Human audit decision for one scanned input file.
enum ManualAuditDecisionValue: String, CaseIterable, Codable, Hashable {
    case valid
    case unsure
    case invalid

    var title: String {
        switch self {
        case .valid:
            Strings.ManualAuditOverview.valid
        case .unsure:
            Strings.ManualAuditOverview.unsure
        case .invalid:
            Strings.ManualAuditOverview.invalid
        }
    }
}

/// SwiftData record storing the user's manual audit decision and optional species.
@Model
final class ManualAuditDecision {
    @Attribute(.unique) var id: String
    var projectID: UUID
    var fileRelativePath: String
    var decisionRaw: String
    var notes: String
    var speciesFamily: String?
    var speciesGenus: String?
    var speciesName: String?
    var speciesFullName: String?
    var speciesSelectionsJSON: String?
    var isRemovedFromExport: Bool?
    var userMaxN: Int?
    var createdAt: Date
    var updatedAt: Date?

    init(
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

extension ManualAuditDecision {
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
