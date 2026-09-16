//
//  ProjectSelectionViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/08/2026.
//

import Foundation
import Core
import SwiftUI
import SwiftData

/// Filter groups available on the project-selection screen.
public enum ProjectGroup: CaseIterable {
    case inProgress
    case completed

    public var title: String {
        switch self {
        case .inProgress:
            Strings.ProjectSelection.inProgressGroup
        case .completed:
            Strings.ProjectSelection.completedGroup
        }
    }
}

/// View-ready row data for one persisted project in the project list.
public struct ProjectSelectionRowViewModel: Identifiable {
    /// Stable identifier for row diffing and project actions.
    public let id: UUID
    /// Persisted project represented by the row.
    public let project: Project
    /// Display name of the module that owns the project workflow.
    public let moduleTitle: String
    /// SF Symbol name used to represent the owning module.
    public let moduleIconName: String
    /// Indicates whether the project folder is currently reachable.
    public let folderExists: Bool
    /// Display title for the current workflow state.
    public let statusTitle: String
    /// Display color for the current workflow state.
    public let statusColor: Color
    /// Summary of completion or latest audit progress.
    public let lastCompletedText: String
    /// Optional recorder/camera identifier display text.
    public let recorderText: String?
    /// Optional last-opened timestamp display text.
    public let lastOpenedText: String?
    /// Primary button title for opening or continuing the project.
    public let primaryActionTitle: String

    public init(
        id: UUID,
        project: Project,
        moduleTitle: String,
        moduleIconName: String,
        folderExists: Bool,
        statusTitle: String,
        statusColor: Color,
        lastCompletedText: String,
        recorderText: String?,
        lastOpenedText: String?,
        primaryActionTitle: String
    ) {
        self.id = id
        self.project = project
        self.moduleTitle = moduleTitle
        self.moduleIconName = moduleIconName
        self.folderExists = folderExists
        self.statusTitle = statusTitle
        self.statusColor = statusColor
        self.lastCompletedText = lastCompletedText
        self.recorderText = recorderText
        self.lastOpenedText = lastOpenedText
        self.primaryActionTitle = primaryActionTitle
    }
}

/// Defines presentation building and project-list actions for project selection.
@MainActor
public protocol ProjectSelectionViewModelType {
    /// Projects visible for the active group and search query.
    var filteredProjects: [Project] { get }

    /// Returns the number of projects in a project-list group.
    func count(for group: ProjectGroup) -> Int
    /// Builds the view-ready row state for one project.
    func row(for project: Project) -> ProjectSelectionRowViewModel
    /// Opens an available project or its read-only database state when its folder is missing.
    func openProject(_ project: Project, folderExists: Bool, coordinator: AppCoordinating)
    /// Returns whether the project folder can currently be reached.
    func projectFolderExists(_ project: Project) -> Bool
    /// Deletes a project and its persisted audit decisions, returning an error message on failure.
    func deleteProject(_ project: Project, modelContext: ModelContext, dependencies: SharedAppDependencies) -> String?
    /// Returns module-owned review progress for a project.
    func auditProgress(for project: Project, modelContext: ModelContext, projectScanService: ProjectScanServicing) -> ProjectSelectionProgress
    /// Loads the project's scan summary when available.
    func summary(for project: Project, projectScanService: ProjectScanServicing) -> ProjectScanSummary?
    /// Preheats previews for the most recent project so continuation feels immediate.
    func preheatLatestProjectPreviews(projects: [Project], modelContext: ModelContext, dependencies: SharedAppDependencies)
}

/// View model that builds deterministic, testable project-selection state.
public struct ProjectSelectionViewModel: ProjectSelectionViewModelType {
    typealias AuditProgressProvider = (Project) -> ProjectSelectionProgress
    typealias SummaryProvider = (Project) -> ProjectScanSummary?
    typealias FolderExistsProvider = (Project) -> Bool

    public let projects: [Project]
    public let selectedGroup: ProjectGroup
    public let searchText: String
    public let moduleCatalog: ModuleCatalog
    let auditProgress: AuditProgressProvider
    let summary: SummaryProvider
    private let folderExists: FolderExistsProvider

    public init(
        projects: [Project],
        selectedGroup: ProjectGroup,
        searchText: String,
        moduleCatalog: ModuleCatalog,
        auditProgress: @escaping (Project) -> ProjectSelectionProgress,
        summary: @escaping (Project) -> ProjectScanSummary?,
        folderExists: @escaping (Project) -> Bool
    ) {
        self.projects = projects
        self.selectedGroup = selectedGroup
        self.searchText = searchText
        self.moduleCatalog = moduleCatalog
        self.auditProgress = auditProgress
        self.summary = summary
        self.folderExists = folderExists
    }

    /// Projects that belong to the selected group and match the current search text.
    public var filteredProjects: [Project] {
        projects.filter { project in
            group(for: project) == selectedGroup && matchesSearch(project)
        }
    }

    /// Returns the number of projects in a group.
    public func count(for group: ProjectGroup) -> Int {
        projects.filter { self.group(for: $0) == group }.count
    }

    /// Creates the renderable row model for a project.
    public func row(for project: Project) -> ProjectSelectionRowViewModel {
        project.normalizeWorkflowStatus()
        let moduleDetails = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))?.details
        let modulePresentation = projectSelectionPresentation(for: project)
        let exists = folderExists(project)
        return ProjectSelectionRowViewModel(
            id: project.id,
            project: project,
            moduleTitle: moduleDetails?.name ?? project.moduleID,
            moduleIconName: moduleDetails?.iconName ?? Icons.folder,
            folderExists: exists,
            statusTitle: exists ? modulePresentation.statusTitle : Strings.ProjectSelection.missingFolder,
            statusColor: exists ? statusColor(project.workflowStatus) : AppColors.error,
            lastCompletedText: lastCompletedText(for: project, presentation: modulePresentation),
            recorderText: project.metadataSummaryValue.map { "\(Strings.ProjectSelection.recorderPrefix) \($0)" },
            lastOpenedText: project.lastOpenedAt.map {
                "\(Strings.ProjectSelection.lastOpenedPrefix) \($0.formatted(date: .abbreviated, time: .shortened))"
            },
            primaryActionTitle: exists ? modulePresentation.primaryActionTitle : Strings.ProjectSelection.viewAvailableDataButton
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
            moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))?.details.name ?? project.moduleID,
            project.moduleID,
            projectSelectionPresentation(for: project).statusTitle,
            project.metadataSummaryValue ?? "",
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
                    file.format ?? "",
                    file.qualityFlag,
                    file.qualityReasons.joined(separator: " "),
                    file.attributes.values.map(\.searchText).joined(separator: " ")
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
        case .inProgress, .scanInProgress, .manualAuditInProgress, .detectionReviewInProgress:
            .secondary
        default:
            .primary
        }
    }

    private func projectSelectionPresentation(for project: Project) -> ProjectSelectionPresentation {
        let module = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))
        return module?.projectSelectionPresentation(
            for: project,
            folderExists: folderExists(project),
            auditProgressText: auditProgressText(for: project)
        ) ?? ProjectSelectionPresentation(
            statusTitle: Strings.WorkflowStatus.inProgress,
            primaryActionTitle: Strings.WorkflowStatus.viewProject,
            lastCompletedStepTitle: Strings.WorkflowStatus.created
        )
    }

    private func lastCompletedText(for project: Project, presentation: ProjectSelectionPresentation) -> String {
        return "\(Strings.ProjectSelection.lastCompletedPrefix) \(presentation.lastCompletedStepTitle)"
    }

    private func auditProgressText(for project: Project) -> String {
        let progress = auditProgress(project)
        guard progress.total > 0 else {
            return Strings.ProjectSelection.zeroReviewed
        }

        let displayedProgress = inProgressReviewStatuses.contains(project.workflowStatus)
            ? progress.displayPosition
            : progress.reviewed
        return String(format: Strings.ProjectSelection.progressFormat, displayedProgress, progress.total)
    }

    private var inProgressReviewStatuses: Set<ProjectWorkflowStatus> {
        [.manualAuditInProgress, .detectionReviewInProgress, .inProgress]
    }

    public func openProject(_ project: Project, folderExists: Bool, coordinator: AppCoordinating) {
        if folderExists {
            coordinator.continueProject(project)
        } else {
            coordinator.openReadOnlyProject(project)
        }
    }

    public func projectFolderExists(_ project: Project) -> Bool {
        Self.projectFolderExists(project)
    }

    public static func projectFolderExists(_ project: Project) -> Bool {
        guard let rootFolderURL = project.rootFolderURL else {
            return false
        }

        let accessed = rootFolderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                rootFolderURL.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: rootFolderURL.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    public func deleteProject(_ project: Project, modelContext: ModelContext, dependencies: SharedAppDependencies) -> String? {
        do {
            try dependencies.projectFileService.deleteProjectFolder(for: project)
            deleteAuditDecisions(for: project, modelContext: modelContext)
            modelContext.delete(project)
            try modelContext.save()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    public func auditProgress(
        for project: Project,
        modelContext: ModelContext,
        projectScanService: ProjectScanServicing
    ) -> ProjectSelectionProgress {
        Self.auditProgress(for: project, modelContext: modelContext, projectScanService: projectScanService)
    }

    public static func auditProgress(
        for project: Project,
        modelContext: ModelContext,
        projectScanService: ProjectScanServicing
    ) -> ProjectSelectionProgress {
        let summary = summary(for: project, projectScanService: projectScanService)
        return ProjectSelectionProgress(project: project, modelContext: modelContext, files: summary?.files ?? [])
    }

    public func summary(for project: Project, projectScanService: ProjectScanServicing) -> ProjectScanSummary? {
        Self.summary(for: project, projectScanService: projectScanService)
    }

    public static func summary(for project: Project, projectScanService: ProjectScanServicing) -> ProjectScanSummary? {
        try? projectScanService.loadSummary(for: project)
    }

    public func preheatLatestProjectPreviews(projects: [Project], modelContext: ModelContext, dependencies: SharedAppDependencies) {
        let latestProjects = projects
            .filter(Self.projectFolderExists)
            .sorted {
                ($0.lastOpenedAt ?? $0.createdAt) > ($1.lastOpenedAt ?? $1.createdAt)
            }
            .prefix(3)

        for project in latestProjects {
            moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))?.preheatProjectPreviews(
                project: project,
                modelContext: modelContext,
                dependencies: dependencies
            )
        }
    }

    private func deleteAuditDecisions(for project: Project, modelContext: ModelContext) {
        Self.deleteAuditDecisions(for: project, modelContext: modelContext)
    }

    private static func deleteAuditDecisions(for project: Project, modelContext: ModelContext) {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        guard let decisions = try? modelContext.fetch(descriptor) else { return }

        for decision in decisions {
            modelContext.delete(decision)
        }
    }

}
