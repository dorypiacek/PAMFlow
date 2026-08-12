//
//  ProjectSelectionModel.swift
//  PAMFlow
//
//  Created by Codex on 12/08/2026.
//

import Foundation
import SwiftUI

/// Project list grouping used by the project-selection screen.
enum ProjectGroup: CaseIterable {
    case inProgress
    case completed

    var title: String {
        switch self {
        case .inProgress:
            Strings.ProjectSelection.inProgressGroup
        case .completed:
            Strings.ProjectSelection.completedGroup
        }
    }
}

/// View-ready row data for one persisted project.
struct ProjectSelectionRowModel: Identifiable {
    let id: UUID
    let project: Project
    let moduleTitle: String
    let moduleIconName: String
    let folderExists: Bool
    let statusTitle: String
    let statusColor: Color
    let lastCompletedText: String
    let recorderText: String?
    let lastOpenedText: String?
    let primaryActionTitle: String
}

/// Builds deterministic, testable presentation state for project selection.
struct ProjectSelectionModel {
    typealias AuditProgressProvider = (Project) -> (reviewed: Int, total: Int)
    typealias SummaryProvider = (Project) -> ProjectScanSummary?
    typealias FolderExistsProvider = (Project) -> Bool

    let projects: [Project]
    let selectedGroup: ProjectGroup
    let searchText: String
    let auditProgress: AuditProgressProvider
    let summary: SummaryProvider
    let folderExists: FolderExistsProvider

    /// Projects that belong to the selected group and match the current search text.
    var filteredProjects: [Project] {
        projects.filter { project in
            group(for: project) == selectedGroup && matchesSearch(project)
        }
    }

    /// Returns the number of projects in a group.
    func count(for group: ProjectGroup) -> Int {
        projects.filter { self.group(for: $0) == group }.count
    }

    /// Creates the renderable row model for a project.
    func row(for project: Project) -> ProjectSelectionRowModel {
        let module = WorkflowModule.module(for: project.moduleID)
        let exists = folderExists(project)
        return ProjectSelectionRowModel(
            id: project.id,
            project: project,
            moduleTitle: module.title,
            moduleIconName: iconName(for: module),
            folderExists: exists,
            statusTitle: exists ? workflowStatusTitle(for: project, module: module) : Strings.ProjectSelection.missingFolder,
            statusColor: exists ? statusColor(project.workflowStatus) : AppColors.error,
            lastCompletedText: lastCompletedText(for: project, module: module),
            recorderText: project.metadataOpcode.map { "\(Strings.ProjectSelection.recorderPrefix) \($0)" },
            lastOpenedText: project.lastOpenedAt.map {
                "\(Strings.ProjectSelection.lastOpenedPrefix) \($0.formatted(date: .abbreviated, time: .shortened))"
            },
            primaryActionTitle: exists ? continueActionTitle(for: project, module: module) : Strings.ProjectSelection.viewAvailableDataButton
        )
    }

    private func group(for project: Project) -> ProjectGroup {
        project.workflowStatus == .completed ? .completed : .inProgress
    }

    private func matchesSearch(_ project: Project) -> Bool {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return searchableText(for: project).localizedCaseInsensitiveContains(trimmed)
    }

    private func searchableText(for project: Project) -> String {
        var values = [
            project.name,
            project.id.uuidString,
            WorkflowModule.module(for: project.moduleID).title,
            project.moduleID,
            project.workflowStatus.title,
            project.metadataOpcode ?? "",
            project.rootFolderURL?.path ?? "",
            project.inputFolderURL?.path ?? "",
            project.rawInputFolderURL?.path ?? ""
        ]

        if let summary = summary(project) {
            values.append(summary.projectName)
            values.append(summary.inputFolder)
            values.append(contentsOf: summary.files.flatMap { file in
                [
                    file.fileName,
                    file.relativePath,
                    file.sourceVideo ?? "",
                    file.format ?? "",
                    file.qualityFlag,
                    file.qualityReasons.joined(separator: " ")
                ]
            })
            values.append(contentsOf: summary.warnings)
        }

        return values.joined(separator: "\n")
    }

    private func statusColor(_ status: ProjectWorkflowStatus) -> Color {
        switch status {
        case .completed:
            AppColors.success
        case .scanInProgress, .manualAuditInProgress, .detectionReviewInProgress:
            .secondary
        default:
            .primary
        }
    }

    private func workflowStatusTitle(for project: Project, module: WorkflowModule) -> String {
        if module.requiresSharkTrack, project.workflowStatus == .processingProjectCreated {
            return Strings.ProjectSelection.processingCompleted
        }

        if module.usesPAMGuard, project.workflowStatus == .processingProjectCreated {
            return Strings.ProjectSelection.waitingForPamguard
        }

        if module.requiresSharkTrack {
            switch project.workflowStatus {
            case .processingProjectCreated, .manualAuditInProgress:
                return Strings.ProjectSelection.frameReviewInProgress
            case .manualAuditCompleted:
                return Strings.ProjectSelection.frameReviewCompleted
            default:
                break
            }
        }

        return project.workflowStatus.title
    }

    private func continueActionTitle(for project: Project, module: WorkflowModule) -> String {
        if module.requiresSharkTrack {
            switch project.workflowStatus {
            case .scanCompleted:
                return Strings.ProjectSelection.startProcessingButton
            case .processingProjectCreated:
                return Strings.ProjectSelection.startFrameReviewButton
            case .manualAuditInProgress:
                return Strings.ProjectSelection.continueFrameReviewButton
            default:
                break
            }
        }

        if module.usesPAMGuard, project.workflowStatus == .processingProjectCreated {
            return Strings.ProjectSelection.openPamguardWaitingButton
        }

        return project.workflowStatus.continueActionTitle
    }

    private func lastCompletedText(for project: Project, module: WorkflowModule) -> String {
        let status = project.workflowStatus
        if module.requiresSharkTrack, status == .processingProjectCreated {
            return "\(Strings.ProjectSelection.lastCompletedPrefix) \(Strings.ProjectSelection.processingCompleted)"
        }

        if module.usesPAMGuard, status == .processingProjectCreated {
            return "\(Strings.ProjectSelection.lastCompletedPrefix) \(Strings.ProjectSelection.pamguardSetupCompleted)"
        }

        if status == .manualAuditInProgress || status == .manualAuditCompleted {
            let progressLabel = module.requiresSharkTrack
                ? Strings.ProjectSelection.frameReviewProgressPrefix
                : Strings.ProjectSelection.manualAuditProgressPrefix
            return "\(Strings.ProjectSelection.lastCompletedPrefix) \(progressLabel) \(auditProgressText(for: project))"
        }

        return "\(Strings.ProjectSelection.lastCompletedPrefix) \(status.lastCompletedStepTitle)"
    }

    private func auditProgressText(for project: Project) -> String {
        let progress = auditProgress(project)
        guard progress.total > 0 else {
            return Strings.ProjectSelection.zeroReviewed
        }

        return String(format: Strings.ManualAuditOverview.reviewedFormat, progress.reviewed, progress.total)
    }

    private func iconName(for module: WorkflowModule) -> String {
        switch module {
        case .pamAudio:
            Icons.audio
        case .bruvVideo:
            Icons.video
        case .ruvImages:
            Icons.image
        }
    }
}
