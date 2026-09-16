//
//  ProjectCompletionView.swift
//  PAMFlow
//
//  Created by Dory on 14/09/2026.
//

import Core
import SwiftData
import SwiftUI

/// Shared completion screen used by feature modules.
///
/// The view renders generic project, scan, and audit state. Module-specific
/// behavior belongs in the injected `ProjectCompletionViewModel` subclass.
public struct ProjectCompletionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCoordinator) private var appCoordinator

    @State private var viewModel: ProjectCompletionViewModel

    public init(viewModel: ProjectCompletionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            if let project = viewModel.fetchProject(modelContext: modelContext), let summary = viewModel.summary {
                let decisions = viewModel.auditDecisions(for: project, modelContext: modelContext)
                let exportFields = viewModel.activeExportFields()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        header
                        completionHighlights(project: project, summary: summary, decisions: decisions)
                        overview(project: project, summary: summary, decisions: decisions)
                        reportFieldsPreview(exportFields)

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(AppColors.error)
                        }
                    }
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .safeAreaInset(edge: .bottom) {
                    actionBar(project: project, decisions: decisions, fields: exportFields)
                }
            } else if let project = viewModel.fetchProject(modelContext: modelContext), let errorMessage = viewModel.errorMessage {
                unavailableProjectContent(project: project, message: errorMessage)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.background)
        .task {
            viewModel.loadSummary(modelContext: modelContext)
        }
        .sheet(isPresented: $viewModel.isCustomisingFields) {
            ExportFieldCustomisationSheet(
                fields: viewModel.availableExportFields,
                selectedFieldIDs: viewModel.activeExportFieldIDs(),
                onSave: viewModel.saveExportFieldIDs,
                onClose: { viewModel.isCustomisingFields = false }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(viewModel.configuration.title)
                .font(Fonts.screenTitle)
            Text(viewModel.configuration.subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overview(project: Project, summary: ProjectScanSummary, decisions: [ManualAuditDecision]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(viewModel.configuration.overviewTitle)
                .font(Fonts.sectionTitle)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                alignment: .leading,
                spacing: Spacing.small
            ) {
                ForEach(viewModel.metrics(project: project, summary: summary, decisions: decisions, appCoordinator: requiredCoordinator)) { metric in
                    if metric.title == Strings.ProjectCompletion.inputFolder || metric.title == Strings.ProjectCompletion.projectFolder {
                        overviewPathMetric(metric.title, metric.value)
                    } else {
                        overviewMetric(metric.title, metric.value)
                    }
                }
            }
        }
        .padding(Spacing.medium)
        .glassySurface()
    }

    private func unavailableProjectContent(project: Project, message: String) -> some View {
        let decisions = viewModel.auditDecisions(for: project, modelContext: modelContext)
        let valid = decisions.filter { $0.decision == .valid }.count
        let unsure = decisions.filter { $0.decision == .unsure }.count
        let invalid = decisions.filter { $0.decision == .invalid }.count

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                header

                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text(Strings.ProjectCompletion.folderUnavailableTitle)
                        .font(Fonts.sectionTitle)
                    Text(Strings.ProjectCompletion.folderUnavailableMessage)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .foregroundStyle(AppColors.error)
                }
                .padding(Spacing.large)
                .glassySurface()

                HighlightBlockView(
                    count: "\(decisions.count)",
                    title: Strings.ProjectCompletion.savedDecisions,
                    metrics: [
                        HighlightMetric(viewModel.configuration.validDecisionsTitle, "\(valid)", valueColor: AppColors.success),
                        HighlightMetric(viewModel.configuration.unsureDecisionsTitle, "\(unsure)"),
                        HighlightMetric(viewModel.configuration.invalidDecisionsTitle, "\(invalid)", valueColor: invalid == 0 ? .primary : AppColors.error),
                        HighlightMetric(Strings.Common.status, viewModel.statusTitle(for: project, appCoordinator: requiredCoordinator))
                    ]
                )

                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text(Strings.ProjectCompletion.projectOverview)
                        .font(Fonts.sectionTitle)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                        alignment: .leading,
                        spacing: Spacing.small
                    ) {
                        overviewMetric(Strings.ProjectCompletion.project, project.name)
                        overviewMetric(Strings.ProjectCompletion.type, viewModel.moduleName(for: project, appCoordinator: requiredCoordinator))
                        overviewMetric(Strings.ProjectCompletion.processedBy, viewModel.processedBy(for: project, appCoordinator: requiredCoordinator))
                        overviewMetric(Strings.Common.status, viewModel.statusTitle(for: project, appCoordinator: requiredCoordinator))
                        if let rootFolderURL = project.rootFolderURL {
                            overviewPathMetric(Strings.ProjectCompletion.projectFolder, rootFolderURL.path)
                        }
                        if let inputFolderURL = project.inputFolderURL {
                            overviewPathMetric(Strings.ProjectCompletion.inputFolder, inputFolderURL.path)
                        }
                        ForEach(viewModel.metadataMetrics(for: project)) { metric in
                            overviewMetric(metric.title, metric.value)
                        }
                    }
                }
                .padding(Spacing.medium)
                .glassySurface()

                HStack(spacing: Spacing.medium) {
                    Button(Strings.Common.backToProjects) {
                        requiredCoordinator.openProjectSelection()
                    }
                    .buttonStyle(.primaryAction)

                    Button(Strings.ProjectCompletion.deleteProject, role: .destructive) {
                        viewModel.deleteUnavailableProject(project, modelContext: modelContext, appCoordinator: requiredCoordinator)
                    }
                    .buttonStyle(.secondaryAction)
                }
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func completionHighlights(project: Project, summary: ProjectScanSummary, decisions: [ManualAuditDecision]) -> some View {
        let valid = decisions.filter { $0.decision == .valid }.count
        let unsure = decisions.filter { $0.decision == .unsure }.count
        let invalid = decisions.filter { $0.decision == .invalid }.count

        return HighlightBlockView(
            count: "\(decisions.count)",
            title: Strings.ProjectCompletion.savedDecisions,
            metrics: [
                HighlightMetric("Processed detections", "\(summary.fileCount)"),
                HighlightMetric(viewModel.configuration.validDecisionsTitle, "\(valid)", valueColor: AppColors.success),
                HighlightMetric(viewModel.configuration.unsureDecisionsTitle, "\(unsure)"),
                HighlightMetric(viewModel.configuration.invalidDecisionsTitle, "\(invalid)", valueColor: invalid == 0 ? .primary : AppColors.error),
                HighlightMetric(Strings.Common.status, viewModel.statusTitle(for: project, appCoordinator: requiredCoordinator))
            ]
        )
    }

    private func actionBar(project: Project, decisions: [ManualAuditDecision], fields: [ProjectCompletionExportField]) -> some View {
        HStack(spacing: Spacing.medium) {
            if let exportButtonTitle = viewModel.configuration.exportButtonTitle {
                Button(exportButtonTitle) {
                    viewModel.export(project: project, decisions: decisions, fields: fields, modelContext: modelContext, appCoordinator: requiredCoordinator)
                }
                .buttonStyle(.primaryAction)
                .disabled(!viewModel.availableExportFields.isEmpty && fields.isEmpty)
            }

            Button(viewModel.configuration.completeButtonTitle) {
                viewModel.complete(project: project, modelContext: modelContext, appCoordinator: requiredCoordinator)
            }
            .buttonStyle(viewModel.configuration.exportButtonTitle == nil ? .primaryAction : .secondaryAction)

            Button(viewModel.configuration.backToProjectsButtonTitle) {
                requiredCoordinator.openProjectSelection()
            }
            .buttonStyle(.secondaryAction)

            if let successMessage = viewModel.successMessage {
                Text(successMessage)
                    .font(Fonts.caption)
                    .foregroundStyle(AppColors.success)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.medium)
        .background(.ultraThinMaterial)
    }

    private func overviewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? Strings.Common.unknown : value)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.small)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    private func overviewPathMetric(_ title: String, _ path: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            ClickablePathText(path: path)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.small)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
    }

    private var requiredCoordinator: any AppCoordinating {
        guard let appCoordinator else {
            fatalError("App coordinator must be injected before rendering project completion")
        }
        return appCoordinator
    }
}

private extension ProjectCompletionView {
    func reportFieldsPreview(_ fields: [ProjectCompletionExportField]) -> some View {
        guard !viewModel.availableExportFields.isEmpty else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.medium) {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(Strings.ProjectCompletion.reportFields)
                            .font(Fonts.sectionTitle)
                        Text(Strings.ProjectCompletion.reportFieldsSubtitle)
                            .font(Fonts.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(Strings.ProjectCompletion.customiseFields) {
                        viewModel.isCustomisingFields = true
                    }
                    .buttonStyle(.secondaryAction)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), alignment: .leading)],
                    alignment: .leading,
                    spacing: Spacing.small
                ) {
                    ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
                        HStack(spacing: Spacing.small) {
                            Text("\(index + 1)")
                                .font(Fonts.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(field.title)
                                .font(Fonts.body.weight(.semibold))
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.medium)
                        .padding(.vertical, Spacing.small)
                        .background(
                            .thinMaterial,
                            in: RoundedRectangle(cornerRadius: Metrics.Layout.rowCornerRadius, style: .continuous)
                        )
                    }
                }
            }
            .padding(Spacing.large)
            .glassySurface()
        )
    }
}

private struct ExportFieldCustomisationSheet: View {
    let fields: [ProjectCompletionExportField]
    let onSave: ([String]) -> Void
    let onClose: () -> Void

    @State private var selectedFieldIDs: [String]

    init(
        fields: [ProjectCompletionExportField],
        selectedFieldIDs: [String],
        onSave: @escaping ([String]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.fields = fields
        self.onSave = onSave
        self.onClose = onClose
        _selectedFieldIDs = State(initialValue: selectedFieldIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(Strings.ProjectCompletion.customiseFields)
                        .font(Fonts.sectionTitle)
                    Text(Strings.ProjectCompletion.customiseFieldsSubtitle)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.iconAction)
            }

            HStack(alignment: .top, spacing: Spacing.large) {
                selectedFields
                availableFields
            }

            HStack {
                Button(Strings.ProjectCompletion.resetDefaults) {
                    selectedFieldIDs = fields.map(\.id)
                }
                .buttonStyle(.secondaryAction)

                Spacer()

                Button(Strings.Common.cancel, action: onClose)
                    .buttonStyle(.secondaryAction)

                Button(Strings.ProjectCompletion.saveFields) {
                    onSave(selectedFieldIDs)
                    onClose()
                }
                .buttonStyle(.primaryAction)
                .disabled(selectedFieldIDs.isEmpty)
            }
        }
        .padding(Spacing.large)
        .frame(width: 920, height: 640)
        .glassySurface()
    }

    private var selectedFields: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(Strings.ProjectCompletion.selected)
                .font(Fonts.body.bold())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(Array(selectedFieldIDs.enumerated()), id: \.element) { index, fieldID in
                        if let field = fields.first(where: { $0.id == fieldID }) {
                            HStack(spacing: Spacing.small) {
                                Text("\(index + 1)")
                                    .font(Fonts.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                                Text(field.title)
                                    .font(Fonts.body.weight(.semibold))
                                Spacer()
                                Button {
                                    moveSelectedField(from: index, offset: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.iconAction)
                                .disabled(index == 0)
                                Button {
                                    moveSelectedField(from: index, offset: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.iconAction)
                                .disabled(index == selectedFieldIDs.count - 1)
                                Button(role: .destructive) {
                                    selectedFieldIDs.removeAll { $0 == fieldID }
                                } label: {
                                    Image(systemName: "minus")
                                }
                                .buttonStyle(.iconAction)
                                .disabled(field.isRequired)
                            }
                        }
                    }
                }
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassySurface()
    }

    private var availableFields: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(Strings.ProjectCompletion.available)
                .font(Fonts.body.bold())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(fields.filter { !selectedFieldIDs.contains($0.id) }) { field in
                        Button {
                            selectedFieldIDs.append(field.id)
                        } label: {
                            HStack(spacing: Spacing.small) {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.secondary)
                                Text(field.title)
                                    .font(Fonts.body.weight(.semibold))
                                Spacer()
                            }
                            .padding(.vertical, Spacing.small)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassySurface()
    }

    private func moveSelectedField(from index: Int, offset: Int) {
        let destination = index + offset
        guard selectedFieldIDs.indices.contains(index), selectedFieldIDs.indices.contains(destination) else { return }
        selectedFieldIDs.swapAt(index, destination)
    }
}
