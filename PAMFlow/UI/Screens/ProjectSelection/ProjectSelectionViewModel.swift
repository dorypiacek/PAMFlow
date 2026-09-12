//
//  ProjectSelectionViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/08/2026.
//

import Foundation
import SwiftUI
import SwiftData

/// Filter groups available on the project-selection screen.
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

/// View-ready row data for one persisted project in the project list.
struct ProjectSelectionRowViewModel: Identifiable {
    /// Stable identifier for row diffing and project actions.
    let id: UUID
    /// Persisted project represented by the row.
    let project: Project
    /// Display name of the module that owns the project workflow.
    let moduleTitle: String
    /// SF Symbol name used to represent the owning module.
    let moduleIconName: String
    /// Indicates whether the project folder is currently reachable.
    let folderExists: Bool
    /// Display title for the current workflow state.
    let statusTitle: String
    /// Display color for the current workflow state.
    let statusColor: Color
    /// Summary of completion or latest audit progress.
    let lastCompletedText: String
    /// Optional recorder/camera identifier display text.
    let recorderText: String?
    /// Optional last-opened timestamp display text.
    let lastOpenedText: String?
    /// Primary button title for opening or continuing the project.
    let primaryActionTitle: String
}

/// Defines presentation building and project-list actions for project selection.
@MainActor
protocol ProjectSelectionViewModelType {
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
    func deleteProject(_ project: Project, modelContext: ModelContext, dependencies: Dependencies) -> String?
    /// Returns reviewed and total counts for a project.
    func auditProgress(for project: Project, modelContext: ModelContext, projectScanService: ProjectScanServicing) -> (reviewed: Int, total: Int)
    /// Loads the project's scan summary when available.
    func summary(for project: Project, projectScanService: ProjectScanServicing) -> ProjectScanSummary?
    /// Preheats previews for the most recent project so continuation feels immediate.
    func preheatLatestProjectPreviews(projects: [Project], modelContext: ModelContext, dependencies: Dependencies)
}

/// View model that builds deterministic, testable project-selection state.
struct ProjectSelectionViewModel: ProjectSelectionViewModelType {
    typealias AuditProgressProvider = (Project) -> (reviewed: Int, total: Int)
    typealias SummaryProvider = (Project) -> ProjectScanSummary?
    typealias FolderExistsProvider = (Project) -> Bool

    let projects: [Project]
    let selectedGroup: ProjectGroup
    let searchText: String
    let moduleCatalog: ModuleCatalog
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
    func row(for project: Project) -> ProjectSelectionRowViewModel {
        let module = WorkflowModule.module(for: project.moduleID)
        let moduleDetails = moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))?.details
        let exists = folderExists(project)
        return ProjectSelectionRowViewModel(
            id: project.id,
            project: project,
            moduleTitle: moduleDetails?.name ?? project.moduleID,
            moduleIconName: moduleDetails?.iconName ?? Icons.folder,
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
            moduleCatalog.module(for: ModuleID(rawValue: project.moduleID))?.details.name ?? project.moduleID,
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
        return project.workflowStatus.title
    }

    private func continueActionTitle(for project: Project, module: WorkflowModule) -> String {
        return project.workflowStatus.continueActionTitle
    }

    private func lastCompletedText(for project: Project, module: WorkflowModule) -> String {
        let status = project.workflowStatus
        if status == .manualAuditInProgress || status == .manualAuditCompleted {
            return "\(Strings.ProjectSelection.lastCompletedPrefix) \(Strings.ProjectSelection.manualAuditProgressPrefix) \(auditProgressText(for: project))"
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

    func openProject(_ project: Project, folderExists: Bool, coordinator: AppCoordinating) {
        if folderExists {
            coordinator.continueProject(project)
        } else {
            coordinator.openReadOnlyProject(project)
        }
    }

    func projectFolderExists(_ project: Project) -> Bool {
        Self.projectFolderExists(project)
    }

    static func projectFolderExists(_ project: Project) -> Bool {
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

    func deleteProject(_ project: Project, modelContext: ModelContext, dependencies: Dependencies) -> String? {
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

    func auditProgress(
        for project: Project,
        modelContext: ModelContext,
        projectScanService: ProjectScanServicing
    ) -> (reviewed: Int, total: Int) {
        Self.auditProgress(for: project, modelContext: modelContext, projectScanService: projectScanService)
    }

    static func auditProgress(
        for project: Project,
        modelContext: ModelContext,
        projectScanService: ProjectScanServicing
    ) -> (reviewed: Int, total: Int) {
        (
            reviewedCount(for: project, modelContext: modelContext),
            totalAuditFileCount(for: project, projectScanService: projectScanService)
        )
    }

    func summary(for project: Project, projectScanService: ProjectScanServicing) -> ProjectScanSummary? {
        Self.summary(for: project, projectScanService: projectScanService)
    }

    static func summary(for project: Project, projectScanService: ProjectScanServicing) -> ProjectScanSummary? {
        try? projectScanService.loadSummary(for: project)
    }

    func preheatLatestProjectPreviews(projects: [Project], modelContext: ModelContext, dependencies: Dependencies) {
        Self.preheatLatestProjectPreviews(projects: projects, modelContext: modelContext, dependencies: dependencies)
    }

    static func preheatLatestProjectPreviews(projects: [Project], modelContext: ModelContext, dependencies: Dependencies) {
        let latestProjects = projects
            .filter(projectFolderExists)
            .sorted {
                ($0.lastOpenedAt ?? $0.createdAt) > ($1.lastOpenedAt ?? $1.createdAt)
            }
            .prefix(3)

        for project in latestProjects {
            preheatFirstAuditPreview(for: project, modelContext: modelContext, dependencies: dependencies)
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

    private static func reviewedCount(for project: Project, modelContext: ModelContext) -> Int {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }

    private static func totalAuditFileCount(for project: Project, projectScanService: ProjectScanServicing) -> Int {
        do {
            let summary = try projectScanService.loadSummary(for: project)
            return summary.files.count
        } catch {
            return 0
        }
    }

    private static func preheatFirstAuditPreview(for project: Project, modelContext: ModelContext, dependencies: Dependencies) {
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio,
              let inputFolderURL = project.inputFolderURL else { return }

        do {
            var summary = try dependencies.projectScanService.loadSummary(for: project)
            summary.files.sort { suspicionScore($0) > suspicionScore($1) }
            let audioFiles = summary.files.filter { isSupportedAudioPath($0.relativePath) }
            guard let file = firstUndecidedFile(in: audioFiles, project: project, modelContext: modelContext) ?? audioFiles.first else {
                return
            }

            let url = inputFolderURL.appendingPathComponent(file.relativePath)
            dependencies.audioPreviewCacheService.preheat(
                url: url,
                securityScopedURL: inputFolderURL,
                clipStartSeconds: nil,
                clipDurationSeconds: nil
            )
        } catch {
            AppLog.info("Project selection preview preheat failed for '\(project.name)': \(error.localizedDescription)")
        }
    }

    private static func firstUndecidedFile(
        in files: [ProjectScanFile],
        project: Project,
        modelContext: ModelContext
    ) -> ProjectScanFile? {
        files.first { file in
            let id = ManualAuditDecision.makeID(projectID: project.id, fileRelativePath: file.relativePath)
            let descriptor = FetchDescriptor<ManualAuditDecision>(
                predicate: #Predicate { decision in
                    decision.id == id
                }
            )
            return (try? modelContext.fetch(descriptor).first) == nil
        }
    }

    private static func suspicionScore(_ file: ProjectScanFile) -> Double {
        var score = 0.0

        if !file.readable { score += 1_000 }
        if file.qualityFlag.lowercased() != "ok" { score += 100 }
        score += Double(file.qualityReasons.count) * 25
        score += (file.clippingPercent ?? 0) * 10
        score += (file.nearZeroPercent ?? 0)

        if let rms = file.rmsDBFS, rms < -70 {
            score += 40
        }

        if file.durationSeconds == nil {
            score += 30
        }

        return score
    }

    private static func isSupportedAudioPath(_ path: String) -> Bool {
        let supportedExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "mp3", "m4a", "caf"]
        return supportedExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}
