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
/// A project is media-agnostic. Module-specific processing details should live
/// outside this model.
@Model
public final class Project {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date?
    public var lastOpenedAt: Date?
    var workflowStatusRaw: String?
    public var scanStartedAt: Date?
    public var scanCompletedAt: Date?
    /// Reviewer name captured the first time the project is completed.
    ///
    /// This is intentionally optional so existing projects migrate without
    /// requiring a synthetic reviewer value. In-progress projects keep using the
    /// active profile name until completion freezes the value.
    public var completedBy: String? = nil
    
    /// Stable identifier of the active workflow module.
    public var moduleID: String
    /// Module-defined metadata values captured during project setup.
    ///
    /// Keys are owned by the active module. Core persists the values without
    /// interpreting their meaning.
    public var metadataValues: [String: String] = [:]
    /// Metadata field used by generic lists and summaries when a single compact
    /// project identifier is needed.
    public var metadataSummaryFieldID: String? = nil
    /// Security-scoped bookmark for the project root folder.
    public var rootFolderBookmark: Data
    /// Security-scoped bookmark for the originally selected input folder.
    public var inputFolderBookmark: Data
    /// Security-scoped bookmark for the raw media folder selected by the user.
    ///
    /// This may differ from `inputFolderBookmark` when the user selected
    /// individual files and PAMFlow created an internal symlink source folder
    /// for processing.
    public var rawInputFolderBookmark: Data? = nil
    /// Durable scan / detection overview snapshot used when the project folder
    /// or generated resources are no longer available.
    @Attribute(.externalStorage) var scanSummaryData: Data? = nil
    public var scanSummaryUpdatedAt: Date? = nil

    public init(
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

public extension Project {
    var workflowStatus: ProjectWorkflowStatus {
        get {
            guard let workflowStatusRaw else {
                return .created
            }

            return ProjectWorkflowStatus(rawValue: workflowStatusRaw)
        }
        set {
            workflowStatusRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    /// Rewrites legacy workflow tokens to the canonical persisted form when a
    /// project is next saved.
    func normalizeWorkflowStatus() {
        let normalized = workflowStatus.rawValue
        if workflowStatusRaw != normalized {
            workflowStatusRaw = normalized
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

    /// Returns a persisted metadata value for a module-owned field identifier.
    func metadataValue(for fieldID: String) -> String? {
        metadataValues[fieldID]
    }

    /// Replaces all module-owned setup metadata for the project.
    func replaceMetadataValues(_ values: [String: String], summaryFieldID: String?) {
        metadataValues = values
        metadataSummaryFieldID = summaryFieldID
        updatedAt = .now
    }

    /// Returns the module-selected metadata value used in compact project
    /// summaries.
    var metadataSummaryValue: String? {
        guard let metadataSummaryFieldID else { return nil }
        return metadataValues[metadataSummaryFieldID]
    }
}
