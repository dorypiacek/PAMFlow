//
//  NewProjectOverviewView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftData
import SwiftUI

/// Shows the scan summary before the user enters manual audit.
struct NewProjectOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID

    @State private var model: NewProjectOverviewModel
    @State private var showsBackToSetupWarning = false
    @State private var showsBackToScanWarning = false

    init(
        projectID: UUID,
        projectScanService: ProjectScanServicing
    ) {
        self.projectID = projectID
        _model = State(initialValue: NewProjectOverviewModel(projectScanService: projectScanService))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView {
                handleBackNavigation()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xLarge) {
                    header
                    content
                }
                .padding(.bottom, Spacing.large)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task {
            load()
        }
        .alert(
            Strings.NewProjectOverview.cancelTitle,
            isPresented: $showsBackToSetupWarning
        ) {
            Button(Strings.NewProjectOverview.cancelConfirmButton, role: .destructive) {
                removeProjectAndReturnToSetup()
            }

            Button(Strings.NewProjectOverview.cancelDismissButton, role: .cancel) {}
        } message: {
            Text(Strings.NewProjectOverview.cancelMessage)
        }
        .alert(
            Strings.NewProjectOverview.backToScanTitle,
            isPresented: $showsBackToScanWarning
        ) {
            Button(Strings.NewProjectOverview.backToScanConfirmButton, role: .destructive) {
                removeAuditProgressAndGoBackToScan()
            }

            Button(Strings.NewProjectOverview.cancelDismissButton, role: .cancel) {}
        } message: {
            Text(Strings.NewProjectOverview.backToScanMessage)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(Strings.NewProjectOverview.title)
                    .font(Fonts.screenTitle)

                Text(Strings.NewProjectOverview.subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(Spacing.large)
    }

    @ViewBuilder
    private var content: some View {
        if let project = fetchProject(),
           let presentation = model.presentation(
            project: project,
            manualAuditProgress: manualAuditProgress(project: project, total: model.summary?.fileCount ?? 0)
           ) {
            overviewContent(presentation)
        } else if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .foregroundStyle(AppColors.error)
                .padding(.horizontal, Spacing.large)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: Metrics.Layout.loadingCardWidth / 2)
        }
    }

    private func overviewContent(_ presentation: NewProjectOverviewPresentation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            HighlightBlockView(
                count: presentation.highlightCount,
                title: presentation.highlightTitle,
                metrics: presentation.highlightMetrics
            )

            detailCard(presentation)
            warnings(presentation)
            sharkTrackStatus(presentation.sharkTrackStatus)
            actionBar(presentation)
        }
        .padding(.horizontal, Spacing.large)
    }

    private func detailCard(_ presentation: NewProjectOverviewPresentation) -> some View {
        HStack(alignment: .top, spacing: Spacing.large) {
            Image(systemName: presentation.moduleIconName)
                .font(.system(size: Metrics.Layout.overviewModuleIconSize, weight: .semibold))
                .frame(width: Metrics.Layout.overviewModuleIconSize, alignment: .center)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Metrics.Layout.auditOverviewMetricMinWidth), alignment: .leading)],
                alignment: .leading,
                spacing: Spacing.medium
            ) {
                pathMetric(
                    Strings.NewProjectOverview.inputFolder,
                    presentation.project.rawInputFolderURL?.path ?? presentation.summary.inputFolder
                )

                ForEach(presentation.detailMetrics) { metric in
                    metricView(metric.title, metric.value)
                }
            }
        }
        .padding(Spacing.large)
        .glassySurface()
    }

    private func actionBar(_ presentation: NewProjectOverviewPresentation) -> some View {
        HStack {
            Button(presentation.primaryActionTitle) {
                Task {
                    await performPrimaryAction(for: presentation.project)
                }
            }
            .buttonStyle(.primaryAction)
            .disabled(presentation.isPrimaryActionDisabled)

            if presentation.canSkipManualAudit {
                Button(Strings.NewProjectOverview.skipManualAuditButton) {
                    skipManualAudit(project: presentation.project, summary: presentation.summary)
                }
                .buttonStyle(.secondaryAction)
                .help(Strings.NewProjectOverview.skipManualAuditHelp)
            }

            Text(presentation.readinessText)
                .foregroundStyle(presentation.readinessColor)
        }
    }

    @ViewBuilder
    private func warnings(_ presentation: NewProjectOverviewPresentation) -> some View {
        if presentation.showsWarnings {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(Strings.NewProjectOverview.qualityWarnings)
                    .font(Fonts.body.bold())

                ForEach(presentation.warnings, id: \.self) { warning in
                    Text(warning)
                        .foregroundStyle(AppColors.error)
                }
            }
        }
    }

    @ViewBuilder
    private func sharkTrackStatus(_ status: NewProjectOverviewPresentation.SharkTrackStatus) -> some View {
        switch status {
        case .hidden:
            EmptyView()
        case .preparing(let message):
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(Strings.NewProjectOverview.sharkTrackTitle)
                    .font(Fonts.body.bold())

                HStack(spacing: Spacing.small) {
                    ProgressView()
                        .controlSize(.small)

                    Text(message)
                }
                .foregroundStyle(.secondary)
            }
        case .failed(let message):
            sharkTrackStatusMessage(message, color: AppColors.error)
        case .ready(let message):
            sharkTrackStatusMessage(message, color: AppColors.success)
        case .notice(let message):
            sharkTrackStatusMessage(message, color: .secondary)
        }
    }

    private func sharkTrackStatusMessage(_ message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(Strings.NewProjectOverview.sharkTrackTitle)
                .font(Fonts.body.bold())

            Text(message)
                .foregroundStyle(color)
        }
    }

    private func metricView(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .lineLimit(3)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pathMetric(_ title: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)

            ClickablePathText(path: path, lineLimit: 3)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension NewProjectOverviewView {
    func load() {
        guard let project = fetchProject() else { return }
        model.load(project: project)
        prewarmInitialAudioPreviews(project: project)
    }

    @MainActor
    func performPrimaryAction(for project: Project) async {
        model.performPrimaryAction(project: project, coordinator: appCoordinator)
        try? modelContext.save()
    }

    func prewarmInitialAudioPreviews(project: Project) {
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio,
              let summary = model.summary,
              let inputFolderURL = project.inputFolderURL else {
            return
        }

        for file in summary.files.prefix(Metrics.Cache.manualAuditPrewarmCount + 1) where isSupportedAudioPath(file.relativePath) {
            let url = inputFolderURL.appendingPathComponent(file.relativePath)
            appCoordinator.dependencies.audioPreviewCacheService.preheat(
                url: url,
                securityScopedURL: inputFolderURL,
                clipStartSeconds: nil,
                clipDurationSeconds: nil
            )
        }
    }

    func isSupportedAudioPath(_ path: String) -> Bool {
        MediaFileExtensions.previewAudio.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    func manualAuditProgress(project: Project, total: Int) -> String {
        guard total > 0 else {
            return String(format: Strings.NewProjectOverview.reviewedPercentFormat, 0, 0, 0)
        }

        let reviewed = auditDecisionCount(for: project)
        let percent = Int((Double(reviewed) / Double(total) * 100).rounded())
        return String(format: Strings.NewProjectOverview.reviewedPercentFormat, reviewed, total, percent)
    }

    func handleBackNavigation() {
        guard let project = fetchProject() else {
            model.goBack(coordinator: appCoordinator)
            return
        }

        if hasGeneratedDetections(for: project) || auditDecisionCount(for: project) > 0 {
            showsBackToSetupWarning = true
        } else {
            removeProjectAndReturnToSetup()
        }
    }

    func removeProjectAndReturnToSetup() {
        guard let project = fetchProject() else {
            model.openProjectSelection(coordinator: appCoordinator)
            return
        }

        do {
            try appCoordinator.dependencies.projectFileService.deleteProjectFolder(for: project)
            deleteAuditDecisions(for: project)
            modelContext.delete(project)
            try modelContext.save()
        } catch {
            model.errorMessage = error.localizedDescription
            return
        }

        model.openProjectSetup(for: project, coordinator: appCoordinator)
    }

    func hasGeneratedDetections(for project: Project) -> Bool {
        guard let rootFolderURL = project.rootFolderURL else { return false }
        let detectionsURL = rootFolderURL.appendingPathComponent(ProjectFileNames.detectionsDirectory, isDirectory: true)
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: detectionsURL.path, isDirectory: &isDirectory) &&
            isDirectory.boolValue
    }

    func removeAuditProgressAndGoBackToScan() {
        guard let project = fetchProject() else {
            model.goBack(coordinator: appCoordinator)
            return
        }

        deleteAuditDecisions(for: project)
        project.workflowStatus = .scanCompleted
        project.lastOpenedAt = .now
        try? modelContext.save()
        model.goBack(coordinator: appCoordinator)
    }

    func deleteAuditDecisions(for project: Project) {
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

    func skipManualAudit(project: Project, summary: ProjectScanSummary) {
        deleteAuditDecisions(for: project)
        for file in summary.files {
            modelContext.insert(
                ManualAuditDecision(
                    projectID: project.id,
                    fileRelativePath: file.relativePath,
                    decision: .valid
                )
            )
        }
        project.workflowStatus = .manualAuditCompleted
        project.lastOpenedAt = .now
        try? modelContext.save()
        model.openPAMGuardSetup(for: project, coordinator: appCoordinator)
    }

    func auditDecisionCount(for project: Project) -> Int {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }

    func fetchProject() -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
