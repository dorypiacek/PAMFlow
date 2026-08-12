//
//  ProjectCompletionView.swift
//  PAMFlow
//
//  Created by Dory on 04/07/2026.
//

import SwiftData
import SwiftUI

struct ProjectCompletionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID
    let projectScanService: ProjectScanServicing

    @State private var summary: ProjectScanSummary?
    @State private var selectedFieldIDs: [String]?
    @State private var isCustomisingFields = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            if let project = fetchProject(), let summary {
                let module = WorkflowModule.module(for: project.moduleID)
                let decisions = auditDecisions(for: project)
                let fields = activeFields(for: module)

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        header
                        content(project: project, summary: summary, decisions: decisions, fields: fields)
                    }
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .safeAreaInset(edge: .bottom) {
                    completionActionBar(project: project, summary: summary, decisions: decisions, fields: fields)
                }
            } else if let project = fetchProject(), let errorMessage {
                unavailableProjectContent(project: project, message: errorMessage)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppColors.background)
        .task { loadSummary() }
        .sheet(isPresented: $isCustomisingFields) {
            if let project = fetchProject() {
                ExportFieldCustomisationSheet(
                    module: WorkflowModule.module(for: project.moduleID),
                    selectedFieldIDs: activeFieldIDs(for: WorkflowModule.module(for: project.moduleID)),
                    onSave: {
                        let module = WorkflowModule.module(for: project.moduleID)
                        selectedFieldIDs = $0
                        UserDefaults.standard.set($0, forKey: exportFieldDefaultsKey(module))
                    },
                    onClose: { isCustomisingFields = false }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(Strings.ProjectCompletion.title)
                .font(Fonts.screenTitle)
            Text(Strings.ProjectCompletion.subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func content(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        fields: [ProjectExportField]
    ) -> some View {
        return VStack(alignment: .leading, spacing: Spacing.medium) {
            completionHighlights(project: project, summary: summary, decisions: decisions, fields: fields)

            projectOverview(project: project, summary: summary, decisions: decisions, fields: fields)

            reportFieldsPreview(fields)

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppColors.error)
            }
        }
    }

    private func unavailableProjectContent(project: Project, message: String) -> some View {
        let decisions = auditDecisions(for: project)
        let valid = decisions.filter { $0.decision == .valid }.count
        let unsure = decisions.filter { $0.decision == .unsure }.count
        let invalid = decisions.filter { $0.decision == .invalid }.count
        let module = WorkflowModule.module(for: project.moduleID)

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
                        HighlightMetric("Valid", "\(valid)", valueColor: AppColors.success),
                        HighlightMetric("Unsure", "\(unsure)"),
                        HighlightMetric("Invalid", "\(invalid)", valueColor: invalid == 0 ? .primary : AppColors.error),
                        HighlightMetric("Status", project.workflowStatus.title)
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
                        overviewMetric(Strings.ProjectCompletion.type, module.title)
                        overviewMetric(Strings.ProjectCompletion.processedBy, processedBy(for: project))
                        overviewMetric(Strings.Common.status, project.workflowStatus.title)
                        if let rootFolderURL = project.rootFolderURL {
                            overviewPathMetric(Strings.ProjectCompletion.projectFolder, rootFolderURL.path)
                        }
                        if let inputFolderURL = project.inputFolderURL {
                            overviewPathMetric(Strings.ProjectCompletion.inputFolder, inputFolderURL.path)
                        }
                        if module.usesProjectMetadata {
                            overviewMetric(Strings.ProjectCompletion.opcode, project.metadataOpcode ?? Strings.Common.unknown)
                            overviewMetric(module == .pamAudio ? Strings.ProjectCompletion.dateDeployed : Strings.ProjectCompletion.date, project.metadataDate ?? Strings.Common.unknown)
                            if module == .pamAudio {
                                overviewMetric(Strings.ProjectCompletion.dateRetrieved, project.metadataDateRetrieved ?? Strings.Common.unknown)
                            }
                            overviewMetric(Strings.ProjectCompletion.location, project.metadataLocation ?? Strings.Common.unknown)
                            overviewMetric(Strings.ProjectCompletion.depth, project.metadataDepth ?? Strings.Common.unknown)
                            overviewMetric(Strings.ProjectCompletion.bottomType, project.metadataBottomType ?? Strings.Common.unknown)
                            if module != .pamAudio {
                                overviewMetric(Strings.ProjectCompletion.waterTemperature, project.metadataWaterTemperature ?? Strings.Common.unknown)
                            }
                        }
                    }
                }
                .padding(Spacing.medium)
                .glassySurface()

                HStack(spacing: Spacing.medium) {
                    Button(Strings.Common.backToProjects) {
                        appCoordinator.openProjectSelection()
                    }
                    .buttonStyle(.primaryAction)

                    Button(Strings.ProjectCompletion.deleteProject, role: .destructive) {
                        deleteUnavailableProject(project)
                    }
                    .buttonStyle(.secondaryAction)
                }
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func completionActionBar(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        fields: [ProjectExportField]
    ) -> some View {
        HStack(spacing: Spacing.medium) {
            Button(Strings.ProjectCompletion.exportDetections) {
                if WorkflowModule.module(for: project.moduleID) == .pamAudio {
                    exportPAMPackage(project: project, summary: summary, decisions: decisions)
                } else {
                    export(project: project, summary: summary, decisions: decisions, fields: fields, separator: ",", fileExtension: "csv")
                }
            }
            .buttonStyle(.primaryAction)
            .disabled(WorkflowModule.module(for: project.moduleID) != .pamAudio && fields.isEmpty)

            Button(Strings.ProjectCompletion.complete) {
                if completeProject(project, summary: summary) {
                    appCoordinator.openProjectSelection()
                }
            }
            .buttonStyle(.secondaryAction)

            if let successMessage {
                Text(successMessage)
                    .font(Fonts.caption)
                    .foregroundStyle(AppColors.success)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.medium)
        .background(.ultraThinMaterial)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            Text(value)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.auditOverviewCardHeight, alignment: .leading)
        .glassySurface()
    }

    private func reportFieldsPreview(_ fields: [ProjectExportField]) -> some View {
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
                    isCustomisingFields = true
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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.title)
                                .font(Fonts.body.weight(.semibold))
                        }

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
    }

    private func projectOverview(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        fields: [ProjectExportField]
    ) -> some View {
        let module = WorkflowModule.module(for: project.moduleID)
        let processedBy = processedBy(for: project)

        return VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(Strings.ProjectCompletion.projectOverview)
                .font(Fonts.sectionTitle)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)],
                alignment: .leading,
                spacing: Spacing.small
            ) {
                overviewMetric(Strings.ProjectCompletion.project, project.name)
                overviewMetric(Strings.ProjectCompletion.type, module.title)
                overviewMetric(Strings.ProjectCompletion.processedBy, processedBy)
                overviewMetric(Strings.Common.status, project.workflowStatus.title)
                overviewPathMetric(Strings.ProjectCompletion.inputFolder, project.rawInputFolderURL?.path ?? summary.inputFolder)
                overviewMetric("Total size", ByteCountFormatter.string(fromByteCount: Int64(summary.totalSizeBytes), countStyle: .file))
                overviewMetric("Files", "\(summary.fileCount)")
                if module == .pamAudio {
                    overviewMetric("Duration range", durationRange(summary))
                    overviewMetric("Sample rates", summary.sampleRatesHz.map { "\($0) Hz" }.joined(separator: ", "))
                    overviewMetric("Channels", summary.channelCounts.map(String.init).joined(separator: ", "))
                }
                overviewMetric("Formats", summary.formats?.joined(separator: ", ") ?? Strings.Common.unknown)
                if module.usesProjectMetadata {
                    overviewMetric(Strings.ProjectCompletion.opcode, project.metadataOpcode ?? Strings.Common.unknown)
                    overviewMetric(module == .pamAudio ? Strings.ProjectCompletion.dateDeployed : Strings.ProjectCompletion.date, project.metadataDate ?? Strings.Common.unknown)
                    if module == .pamAudio {
                        overviewMetric(Strings.ProjectCompletion.dateRetrieved, project.metadataDateRetrieved ?? Strings.Common.unknown)
                    }
                    overviewMetric(Strings.ProjectCompletion.location, project.metadataLocation ?? Strings.Common.unknown)
                    overviewMetric(Strings.ProjectCompletion.depth, project.metadataDepth ?? Strings.Common.unknown)
                    overviewMetric(Strings.ProjectCompletion.bottomType, project.metadataBottomType ?? Strings.Common.unknown)
                    if module != .pamAudio {
                        overviewMetric(Strings.ProjectCompletion.waterTemperature, project.metadataWaterTemperature ?? Strings.Common.unknown)
                    }
                }
            }
        }
        .padding(Spacing.medium)
        .glassySurface()
    }

    private func completionHighlights(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        fields: [ProjectExportField]
    ) -> some View {
        let valid = decisions.filter { $0.decision == .valid }.count
        let unsure = decisions.filter { $0.decision == .unsure }.count
        let invalid = decisions.filter { $0.decision == .invalid }.count
        let module = WorkflowModule.module(for: project.moduleID)
        let title = module == .pamAudio ? "audio detections reviewed" : "detections reviewed"

        return HighlightBlockView(
            count: "\(decisions.count)",
            title: title,
            metrics: [
                HighlightMetric("Processed detections", "\(summary.fileCount)"),
                HighlightMetric("Valid", "\(valid)", valueColor: AppColors.success),
                HighlightMetric("Unsure", "\(unsure)"),
                HighlightMetric("Invalid", "\(invalid)", valueColor: invalid == 0 ? .primary : AppColors.error),
                HighlightMetric("Status", project.workflowStatus.title)
            ]
        )
    }

    private func overviewMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
        VStack(alignment: .leading, spacing: 2) {
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

    private func durationRange(_ summary: ProjectScanSummary) -> String {
        guard let min = summary.durationMinSeconds, let max = summary.durationMaxSeconds else {
            return Strings.Common.unknown
        }

        return "\(formatDuration(min)) - \(formatDuration(max))"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func activeFields(for module: WorkflowModule) -> [ProjectExportField] {
        activeFieldIDs(for: module).compactMap { ProjectExportField.field(id: $0, module: module) }
    }

    private func activeFieldIDs(for module: WorkflowModule) -> [String] {
        if let selectedFieldIDs {
            return selectedFieldIDs
        }
        if let saved = UserDefaults.standard.stringArray(forKey: exportFieldDefaultsKey(module)) {
            return ProjectExportField.includingRequiredDefaults(saved, for: module)
        }
        return ProjectExportField.defaults(for: module).map(\.id)
    }

    private func export(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        fields: [ProjectExportField],
        separator: String,
        fileExtension: String
    ) {
        guard let url = appCoordinator.dependencies.fileSelectionService.selectSaveDestination(
            defaultName: "\(project.name)_detections.\(fileExtension)",
            canCreateDirectories: true
        ) else { return }

        do {
            let report = ProjectExportReport(
                project: project,
                summary: summary,
                decisions: decisions,
                fields: fields,
                separator: separator,
                processedBy: processedBy(for: project)
            )
            try report.string.write(to: url, atomically: true, encoding: .utf8)
            if completeProject(project, summary: summary) {
                successMessage = String(format: Strings.ProjectCompletion.exportSuccessFormat, url.lastPathComponent)
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    private func exportPAMPackage(
        project: Project,
        summary: ProjectScanSummary,
        decisions: [ManualAuditDecision]
    ) {
        guard let url = appCoordinator.dependencies.fileSelectionService.selectSaveDestination(
            defaultName: "\(project.name)_detections",
            canCreateDirectories: true
        ) else { return }

        do {
            let exporter = PAMDetectionPackageExporter(
                project: project,
                summary: summary,
                decisions: decisions,
                processedBy: processedBy(for: project)
            )
            try exporter.writePackage(to: url)
            if completeProject(project, summary: summary) {
                successMessage = String(format: Strings.ProjectCompletion.exportSuccessFormat, url.lastPathComponent)
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
            successMessage = nil
        }
    }

    private func exportFieldDefaultsKey(_ module: WorkflowModule) -> String {
        "pamflow.export.fields.\(module.id)"
    }

    private func loadSummary() {
        guard let project = fetchProject() else {
            errorMessage = Strings.Common.projectNotFound
            return
        }

        do {
            summary = try projectScanService.loadSummary(for: project)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteUnavailableProject(_ project: Project) {
        do {
            try appCoordinator.dependencies.projectFileService.deleteProjectFolder(for: project)
            deleteAuditDecisions(for: project)
            modelContext.delete(project)
            try modelContext.save()
            appCoordinator.openProjectSelection()
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

    @discardableResult
    private func completeProject(_ project: Project, summary: ProjectScanSummary) -> Bool {
        if project.completedBy?.trimmed.isEmpty ?? true {
            project.completedBy = currentReviewerName
        }
        project.workflowStatus = .completed
        project.lastOpenedAt = .now
        do {
            if let rootFolderURL = project.rootFolderURL {
                do {
                    try ProjectScanService.writeSummary(summary, projectRootURL: rootFolderURL)
                } catch {
                    AppLog.info("Project completion skipped internal scan summary refresh: \(error.localizedDescription)")
                }
            }
            try project.storeScanSummary(summary)
            try modelContext.save()
            try appCoordinator.dependencies.projectFileService.removeTemporaryArtifacts(for: project)
            return true
        } catch {
            errorMessage = Strings.ProjectCompletion.completionSaveFailed
            return false
        }
    }

    private func auditDecisions(for project: Project) -> [ManualAuditDecision] {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchProject() -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private var currentReviewerName: String {
        appCoordinator.userProfile?.name.trimmed ?? Strings.Common.unknownUser
    }

    private func processedBy(for project: Project) -> String {
        guard let completedBy = project.completedBy?.trimmed, !completedBy.isEmpty else {
            return currentReviewerName
        }

        return completedBy
    }
}

private struct ExportFieldCustomisationSheet: View {
    let module: WorkflowModule
    let onSave: ([String]) -> Void
    let onClose: () -> Void

    @State private var selectedFieldIDs: [String]
    @State private var draggingFieldID: String?

    init(
        module: WorkflowModule,
        selectedFieldIDs: [String],
        onSave: @escaping ([String]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.module = module
        self.onSave = onSave
        self.onClose = onClose
        _selectedFieldIDs = State(initialValue: selectedFieldIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            header

            HStack(alignment: .top, spacing: Spacing.large) {
                selectedFields
                availableFields
            }

            HStack {
                Button(Strings.ProjectCompletion.resetDefaults) {
                    selectedFieldIDs = ProjectExportField.defaults(for: module).map(\.id)
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
        .frame(width: 980, height: 680)
        .glassySurface()
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(Strings.ProjectCompletion.customiseFields)
                    .font(Fonts.sectionTitle)
                Text(Strings.ProjectCompletion.customiseFieldsSubtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.iconAction)
        }
    }

    private var selectedFields: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(Strings.ProjectCompletion.selected)
                        .font(Fonts.body.bold())
                    Text(Strings.ProjectCompletion.selectedSubtitle)
                        .font(Fonts.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(selectedFieldIDs.count)")
                    .font(Fonts.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: Spacing.small) {
                    ForEach(Array(selectedFieldIDs.enumerated()), id: \.element) { index, fieldID in
                        if let field = ProjectExportField.field(id: fieldID, module: module) {
                            selectedFieldRow(field, index: index)
                                .draggable(fieldID) {
                                    fieldDragPreview(field, index: index)
                                }
                                .dropDestination(for: String.self) { droppedFieldIDs, _ in
                                    guard let droppedFieldID = droppedFieldIDs.first else { return false }
                                    moveField(droppedFieldID, before: fieldID)
                                    draggingFieldID = nil
                                    return true
                                } isTargeted: { isTargeted in
                                    draggingFieldID = isTargeted ? fieldID : draggingFieldID == fieldID ? nil : draggingFieldID
                                }
                                .background(
                                    draggingFieldID == fieldID
                                        ? AppColors.accent.opacity(Metrics.Opacity.hoverHighlight)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Metrics.Layout.rowCornerRadius, style: .continuous)
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassySurface()
    }

    private var availableFields: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(Strings.ProjectCompletion.available)
                        .font(Fonts.body.bold())
                    Text(Strings.ProjectCompletion.availableSubtitle)
                        .font(Fonts.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(ProjectExportField.available(for: module).filter { !selectedFieldIDs.contains($0.id) }) { field in
                        Button {
                            selectedFieldIDs.append(field.id)
                        } label: {
                            fieldRow(field, systemImage: "plus.circle")
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

    private func selectedFieldRow(_ field: ProjectExportField, index: Int) -> some View {
        HStack(spacing: Spacing.medium) {
            Text("\(index + 1)")
                .font(Fonts.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            fieldRowText(field)

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
                selectedFieldIDs.removeAll { $0 == field.id }
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.iconAction)
        }
        .padding(.vertical, Spacing.small)
    }

    private func fieldDragPreview(_ field: ProjectExportField, index: Int) -> some View {
        HStack(spacing: Spacing.small) {
            Text("\(index + 1)")
                .font(Fonts.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(field.title)
                .font(Fonts.body.weight(.semibold))
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
        .background(.thinMaterial, in: Capsule())
    }

    private func fieldRow(_ field: ProjectExportField, systemImage: String) -> some View {
        HStack(spacing: Spacing.medium) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            fieldRowText(field)

            Spacer()
        }
        .padding(.vertical, Spacing.small)
        .padding(.horizontal, Spacing.small)
        .contentShape(Rectangle())
    }

    private func fieldRowText(_ field: ProjectExportField) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(field.title)
                .font(Fonts.body.weight(.semibold))
        }
    }

    private func moveSelectedField(from index: Int, offset: Int) {
        let target = index + offset
        guard selectedFieldIDs.indices.contains(index), selectedFieldIDs.indices.contains(target) else { return }
        selectedFieldIDs.swapAt(index, target)
    }

    private func moveField(_ draggedID: String, before targetID: String) {
        guard draggedID != targetID,
              let sourceIndex = selectedFieldIDs.firstIndex(of: draggedID),
              let targetIndex = selectedFieldIDs.firstIndex(of: targetID) else {
            return
        }

        let fieldID = selectedFieldIDs.remove(at: sourceIndex)
        let adjustedTargetIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        selectedFieldIDs.insert(fieldID, at: adjustedTargetIndex)
    }
}
