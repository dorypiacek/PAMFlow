//
//  Project.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation
import SwiftData

/// A user-created PAMFlow project.
///
/// A project is media-agnostic. It can represent PAM audio, BRUV video, RUV images. Module-specific processing details should live outside
/// this model.
@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date?
    var lastOpenedAt: Date?
    var workflowStatusRaw: String?
    var scanStartedAt: Date?
    var scanCompletedAt: Date?
    /// Reviewer name captured the first time the project is completed.
    ///
    /// This is intentionally optional so existing projects migrate without
    /// requiring a synthetic reviewer value. In-progress projects keep using the
    /// active profile name until completion freezes the value.
    var completedBy: String? = nil
    
    /// Stable identifier of the active workflow module
    var moduleID: String
    var metadataOpcode: String? = nil
    var metadataDate: String? = nil
    var metadataDateRetrieved: String? = nil
    var metadataLocation: String? = nil
    var metadataDepth: String? = nil
    var metadataBottomType: String? = nil
    var metadataWaterTemperature: String? = nil
    /// Security-scoped bookmark for the project root folder.
    var rootFolderBookmark: Data
    /// Security-scoped bookmark for the originally selected input folder.
    var inputFolderBookmark: Data
    /// Security-scoped bookmark for the raw media folder selected by the user.
    ///
    /// This may differ from `inputFolderBookmark` when the user selected
    /// individual files and PAMFlow created an internal symlink source folder
    /// for processing.
    var rawInputFolderBookmark: Data? = nil
    /// Durable scan / detection overview snapshot used when the project folder
    /// or generated resources are no longer available.
    @Attribute(.externalStorage) var scanSummaryData: Data? = nil
    var scanSummaryUpdatedAt: Date? = nil

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        workflowStatus: ProjectWorkflowStatus = .created,
        moduleID: String,
        rootFolderBookmark: Data,
        inputFolderBookmark: Data,
        rawInputFolderBookmark: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = nil
        self.workflowStatusRaw = workflowStatus.rawValue
        self.scanStartedAt = nil
        self.scanCompletedAt = nil
        self.moduleID = moduleID
        self.rootFolderBookmark = rootFolderBookmark
        self.inputFolderBookmark = inputFolderBookmark
        self.rawInputFolderBookmark = rawInputFolderBookmark
    }
}

extension Project {
    var workflowStatus: ProjectWorkflowStatus {
        get {
            guard let workflowStatusRaw else {
                return .created
            }

            return ProjectWorkflowStatus(rawValue: workflowStatusRaw) ?? .created
        }
        set {
            workflowStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var rootFolderURL: URL? {
        resolveBookmark(rootFolderBookmark)
    }

    var inputFolderURL: URL? {
        resolveBookmark(inputFolderBookmark)
    }

    var rawInputFolderURL: URL? {
        guard let rawInputFolderBookmark else {
            return inputFolderURL
        }
        return resolveBookmark(rawInputFolderBookmark) ?? inputFolderURL
    }

    private func resolveBookmark(_ bookmark: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    func storeScanSummary(_ summary: ProjectScanSummary) throws {
        scanSummaryData = try ProjectScanService.encodedSummaryData(summary)
        scanSummaryUpdatedAt = .now
        updatedAt = .now
    }
}
