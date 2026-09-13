//
//  NewProjectOverviewView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftData
import SwiftUI

/// Renders scan-summary readiness and forwards overview actions to its ViewModel.
struct NewProjectOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID

    @State private var viewModel: NewProjectOverviewViewModel
    @State private var showsBackToSetupWarning = false
    @State private var showsBackToScanWarning = false

    init(
        projectID: UUID,
        viewModel: NewProjectOverviewViewModel
    ) {
        self.projectID = projectID
        _viewModel = State(initialValue: viewModel)
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
        if let project = viewModel.fetchProject(projectID, modelContext: modelContext),
           let presentation = viewModel.presentation(
            project: project,
            manualAuditProgress: viewModel.manualAuditProgress(
                project: project,
                total: viewModel.summary?.fileCount ?? 0,
                modelContext: modelContext
            )
           ) {
            overviewContent(presentation)
        } else if let errorMessage = viewModel.errorMessage {
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
            moduleProcessingStatus(presentation.moduleProcessingStatus)
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
                    viewModel.skipManualAudit(project: presentation.project, modelContext: modelContext, coordinator: appCoordinator)
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
    private func moduleProcessingStatus(_ status: NewProjectOverviewPresentation.ModuleProcessingStatus) -> some View {
        switch status {
        case .hidden:
            EmptyView()
        case .preparing(let message):
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(Strings.NewProjectOverview.moduleProcessingTitle)
                    .font(Fonts.body.bold())

                HStack(spacing: Spacing.small) {
                    ProgressView()
                        .controlSize(.small)

                    Text(message)
                }
                .foregroundStyle(.secondary)
            }
        case .failed(let message):
            moduleProcessingStatusMessage(message, color: AppColors.error)
        case .ready(let message):
            moduleProcessingStatusMessage(message, color: AppColors.success)
        case .notice(let message):
            moduleProcessingStatusMessage(message, color: .secondary)
        }
    }

    private func moduleProcessingStatusMessage(_ message: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(Strings.NewProjectOverview.moduleProcessingTitle)
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
        guard let project = viewModel.fetchProject(projectID, modelContext: modelContext) else { return }
        viewModel.load(project: project)
    }

    @MainActor
    func performPrimaryAction(for project: Project) async {
        viewModel.performPrimaryAction(project: project, modelContext: modelContext, coordinator: appCoordinator)
    }

    func handleBackNavigation() {
        guard let project = viewModel.fetchProject(projectID, modelContext: modelContext) else {
            viewModel.goBack(coordinator: appCoordinator)
            return
        }

        if viewModel.hasGeneratedArtifacts(for: project, moduleCatalog: appCoordinator.moduleCatalog) ||
            viewModel.auditDecisionCount(for: project, modelContext: modelContext) > 0 {
            showsBackToSetupWarning = true
        } else {
            removeProjectAndReturnToSetup()
        }
    }

    func removeProjectAndReturnToSetup() {
        guard let project = viewModel.fetchProject(projectID, modelContext: modelContext) else {
            viewModel.openProjectSelection(coordinator: appCoordinator)
            return
        }

        viewModel.removeProjectAndReturnToSetup(project: project, modelContext: modelContext, coordinator: appCoordinator)
    }

    func removeAuditProgressAndGoBackToScan() {
        guard let project = viewModel.fetchProject(projectID, modelContext: modelContext) else {
            viewModel.goBack(coordinator: appCoordinator)
            return
        }

        viewModel.removeAuditProgressAndGoBackToScan(project: project, modelContext: modelContext, coordinator: appCoordinator)
    }
}
