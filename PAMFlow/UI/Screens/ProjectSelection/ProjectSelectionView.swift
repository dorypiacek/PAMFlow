//
//  ProjectSelectionView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftData
import SwiftUI

/// Project overview screen for opening, continuing, or deleting existing projects.
struct ProjectSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var errorMessage: String?
    @State private var projectIDPendingDeletion: UUID?
    @State private var selectedProjectGroup: ProjectGroup = .inProgress
    @State private var searchText = ""

    private var presentation: ProjectSelectionModel {
        ProjectSelectionModel(
            projects: projects,
            selectedGroup: selectedProjectGroup,
            searchText: searchText,
            moduleCatalog: appCoordinator.moduleCatalog,
            auditProgress: auditProgress(for:),
            summary: summary(for:),
            folderExists: projectFolderExists(_:)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            VStack(alignment: .leading, spacing: Spacing.large) {
                header

                HStack(alignment: .top, spacing: Spacing.large) {
                    sidebar

                    if projects.isEmpty {
                        emptyProjectCard
                    } else {
                        projectList
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(AppColors.error)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.top, Spacing.large)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppColors.background)
        .task {
            preheatLatestProjectPreviews()
        }
        .alert(
            Strings.ProjectSelection.deleteConfirmationTitle,
            isPresented: Binding(
                get: { projectIDPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        projectIDPendingDeletion = nil
                    }
                }
            )
        ) {
            Button(Strings.ProjectSelection.deleteConfirmationButton, role: .destructive) {
                confirmProjectDeletion()
            }

            Button(Strings.ProjectSelection.deleteConfirmationCancelButton, role: .cancel) {
                projectIDPendingDeletion = nil
            }
        } message: {
            Text(Strings.ProjectSelection.deleteConfirmationMessage)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(Strings.ProjectSelection.title)
                    .font(Fonts.screenTitle)

                Text(Strings.ProjectSelection.subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appCoordinator.openDataTypeSelection()
            } label: {
                Label(Strings.ProjectSelection.newProjectButton, systemImage: Icons.add)
                    .font(Fonts.body.weight(.semibold))
                    .frame(height: Metrics.Layout.auditControlHeight)
                    .padding(.horizontal, Spacing.medium)
            }
            .buttonStyle(.primaryAction)
            .clipShape(.capsule)
        }
    }

    private var emptyProjectCard: some View {
        VStack(alignment: .center, spacing: Spacing.medium) {
            Text(Strings.ProjectSelection.emptyTitle)
                .font(Fonts.sectionTitle)

            Text(Strings.ProjectSelection.emptySubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(Strings.ProjectSelection.newProjectButton) {
                appCoordinator.openDataTypeSelection()
            }
            .buttonStyle(.primaryAction)
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.projectSelectionCardHeight, alignment: .center)
        .glassySurface()
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.medium) {
                if presentation.filteredProjects.isEmpty {
                    Text(Strings.ProjectSelection.noMatchingProjects)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.projectSelectionCardHeight)
                        .glassySurface()
                } else {
                    ForEach(presentation.filteredProjects) { project in
                        projectRow(presentation.row(for: project))
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            TextField(Strings.ProjectSelection.searchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

            ForEach(ProjectGroup.allCases, id: \.self) { group in
                sidebarGroupButton(group)
            }
        }
        .padding(Spacing.large)
        .frame(
            width: 240,
            height: Metrics.Layout.projectSelectionCardHeight,
            alignment: .topLeading
        )
        .glassySurface()
    }

    @ViewBuilder
    private func sidebarGroupButton(_ group: ProjectGroup) -> some View {
        let isSelected = selectedProjectGroup == group
        let label = HStack {
            Text(group.title)
            Spacer()
            Text("\(presentation.count(for: group))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(Fonts.body.weight(.semibold))
        .frame(height: Metrics.Layout.auditControlHeight)
        .padding(.horizontal, Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)

        if isSelected {
            Button {
                selectedProjectGroup = group
            } label: {
                label
            }
            .buttonStyle(.primaryAction)
            .controlSize(.regular)
            .clipShape(.capsule)
        } else {
            Button {
                selectedProjectGroup = group
            } label: {
                label
            }
            .buttonStyle(.prominentSecondaryAction)
            .controlSize(.regular)
            .clipShape(.capsule)
        }
    }

    private func projectRow(_ row: ProjectSelectionRowModel) -> some View {
        HStack(alignment: .center, spacing: Spacing.xLarge) {
                Image(systemName: row.moduleIconName)
                    .font(.system(size: Metrics.Layout.projectCardModuleIconSize, weight: .semibold))
                    .frame(
                        width: Metrics.Layout.projectCardModuleIconSize,
                        height: Metrics.Layout.projectCardModuleIconSize,
                        alignment: .center
                    )
                    .foregroundStyle(.secondary)
                    .help(row.moduleTitle)

                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(row.project.name)
                        .font(Fonts.sectionTitle)

                    Text(row.statusTitle)
                        .foregroundStyle(row.statusColor)

                    Text(row.lastCompletedText)
                        .foregroundStyle(.secondary)

                    HStack(spacing: Spacing.medium) {
                        if let recorderText = row.recorderText {
                            Text(recorderText)
                        }

                        if let lastOpenedText = row.lastOpenedText {
                            Text(lastOpenedText)
                        }
                    }
                    .font(Fonts.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.small) {
                    Button(row.primaryActionTitle) {
                        openProject(row.project, folderExists: row.folderExists)
                    }
                    .buttonStyle(.primaryAction)

                    Button(Strings.ProjectSelection.deleteButton, role: .destructive) {
                        projectIDPendingDeletion = row.project.id
                    }
                    .buttonStyle(.secondaryAction)
                }
            }
            .contentShape(Rectangle())
        .padding(Spacing.large)
        .padding(.leading, Spacing.small)
        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.projectSelectionCardHeight, alignment: .leading)
        .glassySurface()
        .onTapGesture {
            openProject(row.project, folderExists: row.folderExists)
        }
    }

    private func openProject(_ project: Project, folderExists: Bool) {
        if folderExists {
            appCoordinator.continueProject(project)
        } else {
            appCoordinator.openProjectCompletion(project)
        }
    }

    private func projectFolderExists(_ project: Project) -> Bool {
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

    private func confirmProjectDeletion() {
        guard
            let projectIDPendingDeletion,
            let project = projects.first(where: { $0.id == projectIDPendingDeletion })
        else {
            self.projectIDPendingDeletion = nil
            return
        }

        deleteProject(project)
        self.projectIDPendingDeletion = nil
    }

    private func deleteProject(_ project: Project) {
        do {
            try appCoordinator.dependencies.projectFileService.deleteProjectFolder(for: project)
            deleteAuditDecisions(for: project)
            modelContext.delete(project)
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAuditDecisions(for project: Project) {
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

    private func auditProgress(for project: Project) -> (reviewed: Int, total: Int) {
        (reviewedCount(for: project), totalAuditFileCount(for: project))
    }

    private func summary(for project: Project) -> ProjectScanSummary? {
        try? appCoordinator.dependencies.projectScanService.loadSummary(for: project)
    }

    private func reviewedCount(for project: Project) -> Int {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }

    private func totalAuditFileCount(for project: Project) -> Int {
        do {
            let summary = try appCoordinator.dependencies.projectScanService.loadSummary(for: project)
            return summary.files.count
        } catch {
            return 0
        }
    }

    private func preheatLatestProjectPreviews() {
        let latestProjects = projects
            .filter(projectFolderExists)
            .sorted {
                ($0.lastOpenedAt ?? $0.createdAt) > ($1.lastOpenedAt ?? $1.createdAt)
            }
            .prefix(3)

        for project in latestProjects {
            preheatFirstAuditPreview(for: project)
        }
    }

    private func preheatFirstAuditPreview(for project: Project) {
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio,
              let inputFolderURL = project.inputFolderURL else { return }

        do {
            var summary = try appCoordinator.dependencies.projectScanService.loadSummary(for: project)
            summary.files.sort { suspicionScore($0) > suspicionScore($1) }
            let audioFiles = summary.files.filter { isSupportedAudioPath($0.relativePath) }
            guard let file = firstUndecidedFile(in: audioFiles, project: project) ?? audioFiles.first else {
                return
            }

            let url = inputFolderURL.appendingPathComponent(file.relativePath)
            appCoordinator.dependencies.audioPreviewCacheService.preheat(
                url: url,
                securityScopedURL: inputFolderURL,
                clipStartSeconds: nil,
                clipDurationSeconds: nil
            )
        } catch {
            AppLog.info("Project selection preview preheat failed for '\(project.name)': \(error.localizedDescription)")
        }
    }

    private func firstUndecidedFile(in files: [ProjectScanFile], project: Project) -> ProjectScanFile? {
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

    private func suspicionScore(_ file: ProjectScanFile) -> Double {
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

    private func isSupportedAudioPath(_ path: String) -> Bool {
        let supportedExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "mp3", "m4a", "caf"]
        return supportedExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}
