//
//  ManualAuditView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import AppKit
import Core
import SwiftData
import SwiftUI

/// Renders shared manual review controls while modules provide preview content.
public struct ManualAuditView<PreviewContent: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCoordinator) private var appCoordinator

    private var coordinator: any AppCoordinating {
        guard let appCoordinator else {
            fatalError("App coordinator must be injected before rendering shared UI")
        }
        return appCoordinator
    }

    let projectID: UUID
    let startAtLastReviewed: Bool
    private let previewContent: (ManualAuditViewModel, Project, ProjectScanFile) -> PreviewContent
    
    @State private var viewModel: ManualAuditViewModel
    @State private var decisionVersion = 0
    @State private var isShowingSpeciesSelection = false
    @State private var isShowingReasonSelection = false
    @State private var pendingDecisions: [String: ManualAuditDecisionValue] = [:]
    @State private var selectedDecision: ManualAuditDecisionValue?
    @State private var invalidReason = ""
    @State private var maxNText = ""

    public init(
        projectID: UUID,
        startAtLastReviewed: Bool = false,
        viewModel: ManualAuditViewModel,
        @ViewBuilder previewContent: @escaping (ManualAuditViewModel, Project, ProjectScanFile) -> PreviewContent
    ) {
        self.projectID = projectID
        self.startAtLastReviewed = startAtLastReviewed
        self.previewContent = previewContent
        _viewModel = State(initialValue: viewModel)
    }
    
    public var body: some View {
        VStack(spacing: Spacing.large) {
            TopBarView()

            Group {
                if let project = viewModel.fetchProject(projectID, modelContext: modelContext) {
                    auditContent(project: project)
                } else {
                    Text(Strings.Common.projectNotFound)
                        .foregroundStyle(AppColors.error)
                        .padding(Spacing.xxLarge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.bottom, Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task {
            if let project = viewModel.fetchProject(projectID, modelContext: modelContext) {
                viewModel.load(
                    project: project,
                    modelContext: modelContext,
                    startAtLastReviewed: startAtLastReviewed
                )
            }
        }
        .onDisappear {
            viewModel.cancelPreviewWork()
        }
        .sheet(isPresented: $isShowingSpeciesSelection) {
            if let project = viewModel.fetchProject(projectID, modelContext: modelContext), let file = viewModel.selectedFile {
                SpeciesSelectionSheet(
                    taxa: viewModel.speciesTaxa(project: project),
                    drafts: speciesAssignmentDrafts(for: file, project: project),
                    onSave: { drafts in
                        saveSpeciesDrafts(drafts, project: project)
                    },
                    onClose: {
                        isShowingSpeciesSelection = false
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingReasonSelection) {
            if let project = viewModel.fetchProject(projectID, modelContext: modelContext) {
                AuditReasonSelectionSheet(
                    configuration: viewModel.reasonConfiguration(for: project),
                    currentReason: invalidReason,
                    onSave: { reason in
                        setInvalidReason(reason, project: project)
                    },
                    onClose: {
                        isShowingReasonSelection = false
                    }
                )
            }
        }
    }
    
    private func auditContent(project: Project) -> some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            header(project: project)
            
            if let errorMessage = viewModel.errorMessage, viewModel.selectedFile == nil {
                Text(errorMessage)
                    .foregroundStyle(AppColors.error)
            } else if let file = viewModel.selectedFile {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    HStack(alignment: .top, spacing: Spacing.large) {
                        previewContent(viewModel, project, file)
                            .frame(minWidth: 0)
                            .frame(maxWidth: .infinity)
                        
                        ScrollView {
                            evidencePanel(file: file, project: project)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .scrollIndicators(.hidden)
                        .frame(width: Metrics.Layout.evidencePanelWidth, alignment: .leading)
                    }
                    .padding([.horizontal, .top], Spacing.large)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                    decisionControls(project: project)
                        .padding([.horizontal, .bottom], Spacing.large)
                }
                .frame(maxHeight: .infinity)
                .glassySurface()
                .id(file.relativePath)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: file.relativePath)
                .onAppear {
                    syncSelectedDecision(file: file, project: project)
                    syncInvalidReason(file: file, project: project)
                    syncMaxN(file: file, project: project)
                }
                .onChange(of: file.relativePath) { _, _ in
                    syncSelectedDecision(file: file, project: project)
                    syncInvalidReason(file: file, project: project)
                    syncMaxN(file: file, project: project)
                }
            } else {
                ProgressView()
            }
        }
        .padding(.horizontal, Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    
    private func header(project: Project) -> some View {
        return HStack {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(viewModel.reviewTitle(project: project))
                    .font(Fonts.screenTitle)
                
                Text(viewModel.reviewHeaderText(project: project))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
    
    private func evidencePanel(file: ProjectScanFile, project: Project) -> some View {
        let currentDecision = currentDecision(for: file, project: project)

        return VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(Strings.ManualAudit.scanEvidence)
                .font(Fonts.subtitle)
            
            if viewModel.showsFileNameMetric(project: project) {
                metric(Strings.ManualAudit.fileName, viewModel.displaySourceName(for: file, project: project))
            }
            metric(Strings.ManualAudit.decision, currentDecision?.title ?? Strings.ManualAudit.notReviewed)
            if viewModel.showsQualityMetric(project: project) {
                metric(
                    Strings.ManualAudit.quality,
                    file.qualityFlag,
                    valueColor: viewModel.qualityValueColor(file.qualityFlag)
                )
            }

            ForEach(viewModel.evidenceMetrics(file: file, project: project)) { row in
                metric(row.title, row.value, valueColor: row.valueColor)
            }
            if viewModel.canEditMaxN(project: project) {
                editableMaxNMetric(file: file)
            }
        }
    }
    
    private func decisionControls(project: Project) -> some View {
        let requiresInvalidReason = viewModel.reasonConfiguration(for: project).isRequired && selectedDecision == .invalid
        let canNavigate = selectedDecision != nil && (!requiresInvalidReason || !invalidReason.isEmpty)
        return HStack(spacing: Spacing.large) {
            Button {
                movePrevious(project: project)
            } label: {
                auditControlLabel(
                    Strings.ManualAudit.previous,
                    systemImage: "chevron.left"
                )
            }
            .help(Strings.ManualAudit.previousSampleHelp)
            .buttonStyle(.prominentSecondaryAction)
            .controlSize(.regular)
            .disabled(!viewModel.canMovePrevious)

            Spacer()

            HStack(spacing: Spacing.medium) {
                ForEach(viewModel.decisionOptions(project: project), id: \.self) { decision in
                    decisionButton(
                        decision,
                        isSelected: selectedDecision == decision,
                        project: project
                    )
                }

                if viewModel.shouldShowReviewAction(project: project) {
                    detectionActionButton(
                        selectedDecision: selectedDecision,
                        project: project,
                        canNavigate: canNavigate
                    )
                    .transition(.opacity)
                    .id(selectedDecision?.rawValue ?? "none")
                }
            }

            Spacer()

            if viewModel.canMoveNextByIndex {
                Button {
                    moveNext(project: project)
                } label: {
                    auditControlLabel(
                        Strings.ManualAudit.next,
                        systemImage: "chevron.right",
                        iconAfterText: true
                    )
                }
                .help(selectedDecision == nil ? Strings.ManualAudit.chooseDecisionBeforeNextHelp : Strings.ManualAudit.nextSampleHelp)
                .buttonStyle(.prominentSecondaryAction)
                .controlSize(.regular)
                .disabled(!canNavigate)
            } else {
                Button {
                    finishAudit(project: project)
                } label: {
                    auditControlLabel(Strings.ManualAudit.finishAudit)
                }
                .help(selectedDecision == nil ? Strings.ManualAudit.chooseDecisionBeforeFinishHelp : Strings.ManualAudit.openManualAuditOverviewHelp)
                .buttonStyle(.prominentSecondaryAction)
                .controlSize(.regular)
                .disabled(!canNavigate)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func detectionActionButton(
        selectedDecision: ManualAuditDecisionValue?,
        project: Project,
        canNavigate: Bool
    ) -> some View {
        if selectedDecision == .valid, viewModel.canAssignSpecies(project: project) {
            assignSpeciesButton(project: project, canEdit: canNavigate)
        } else if selectedDecision == .invalid || selectedDecision == .unsure {
            addReasonButton(project: project, canEdit: true)
        } else {
            EmptyView()
        }
    }

    private func assignSpeciesButton(project: Project, canEdit: Bool) -> some View {
        let selections = viewModel.selectedFile.map {
            viewModel.speciesSelections(for: $0, project: project, modelContext: modelContext)
        } ?? []
        let title = speciesAssignmentTitle(for: selections)

        return Button {
            isShowingSpeciesSelection = true
        } label: {
            auditControlLabel(selections.isEmpty ? Strings.ManualAudit.assignSpecies : String(format: Strings.ManualAudit.selectedSpeciesPrefixFormat, title))
        }
        .buttonStyle(.prominentSecondaryAction)
        .controlSize(.regular)
        .frame(minWidth: Metrics.Layout.auditActionButtonMinWidth)
        .disabled(!canEdit)
    }

    private func addReasonButton(project: Project, canEdit: Bool) -> some View {
        Button {
            isShowingReasonSelection = true
        } label: {
            auditControlLabel(invalidReason.isEmpty ? Strings.AuditReason.addReason : String(format: Strings.ManualAudit.selectedReasonPrefixFormat, invalidReason))
        }
        .buttonStyle(.prominentSecondaryAction)
        .controlSize(.regular)
        .frame(minWidth: Metrics.Layout.auditActionButtonMinWidth)
        .disabled(!canEdit)
    }

    private func speciesAssignmentTitle(for selections: [SpeciesSelection]) -> String {
        switch selections.count {
        case 1:
            selections[0].fullName
        case 2...:
            String(format: Strings.ManualAudit.speciesAssignedFormat, selections.count)
        default:
            Strings.ManualAudit.assignSpecies
        }
    }
    
    @ViewBuilder
    private func decisionButton(
        _ decision: ManualAuditDecisionValue,
        isSelected: Bool,
        project: Project
    ) -> some View {
        Button {
            withAnimation {
                save(decision, project: project)
            }
        } label: {
            decisionLabel(decision, isSelected: isSelected)
        }
        .buttonStyle(isSelected ? .primaryAction : .prominentSecondaryAction)
        .controlSize(.regular)
        .frame(minWidth: Metrics.Layout.decisionButtonMinWidth)
        .clipShape(.capsule)
    }

    private func decisionLabel(
        _ decision: ManualAuditDecisionValue,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: Spacing.xSmall) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .imageScale(.small)
            Text(decision.title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: Metrics.Layout.auditControlHeight)
        .padding(.horizontal, Spacing.medium)
    }

    private func auditControlLabel(
        _ title: String,
        systemImage: String? = nil,
        iconAfterText: Bool = false
    ) -> some View {
        HStack(spacing: Spacing.xSmall) {
            if let systemImage, !iconAfterText {
                Image(systemName: systemImage)
            }
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let systemImage, iconAfterText {
                Image(systemName: systemImage)
            }
        }
        .frame(height: Metrics.Layout.auditControlHeight)
        .padding(.horizontal, Spacing.small)
    }
    
    private func metric(_ title: String, _ value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .foregroundStyle(valueColor)
        }
    }

    private func editableMaxNMetric(file: ProjectScanFile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(Strings.ManualAudit.maxN)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Button {
                    adjustMaxN(by: -1)
                } label: {
                    Image(systemName: Icons.minus)
                }
                .buttonStyle(.iconAction)
                .disabled((Int(maxNText) ?? 1) <= 1)

                TextField("1", text: $maxNText)
                    .textFieldStyle(.plain)
                    .font(Fonts.body)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(width: 30)
                    .onSubmit {
                        saveMaxNOverride()
                    }

                Button {
                    adjustMaxN(by: 1)
                } label: {
                    Image(systemName: Icons.plus)
                }
                .buttonStyle(.iconAction)
            }
        }
    }

    private func save(_ decision: ManualAuditDecisionValue, project: Project) {
        guard let file = viewModel.selectedFile else { return }
        guard selectedDecision != decision || pendingDecisions[file.relativePath] != decision else { return }
        selectedDecision = decision
        pendingDecisions[file.relativePath] = decision
        decisionVersion += 1

        do {
            try viewModel.saveDecision(decision, project: project, modelContext: modelContext)
            saveMaxNOverride()
            if decision == .invalid || decision == .unsure {
                viewModel.saveInvalidReason(invalidReason, project: project, modelContext: modelContext)
            } else if !invalidReason.isEmpty {
                invalidReason = ""
                viewModel.saveInvalidReason(invalidReason, project: project, modelContext: modelContext)
            }
            decisionVersion += 1
        } catch {
            pendingDecisions[file.relativePath] = nil
            selectedDecision = currentDecision(for: file, project: project)
            decisionVersion += 1
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func syncSelectedDecision(file: ProjectScanFile, project: Project) {
        selectedDecision = currentDecision(for: file, project: project)
    }

    private func setInvalidReason(_ reason: String, project: Project) {
        invalidReason = reason
        viewModel.saveInvalidReason(reason, project: project, modelContext: modelContext)
        decisionVersion += 1
    }

    private func syncInvalidReason(file: ProjectScanFile, project: Project) {
        invalidReason = viewModel.auditDecision(for: file, project: project, modelContext: modelContext)?.notes ?? ""
    }

    private func syncMaxN(file: ProjectScanFile, project: Project) {
        maxNText = viewModel.effectiveMaxN(for: file, project: project, modelContext: modelContext).map(String.init) ?? ""
    }

    private func adjustMaxN(by delta: Int) {
        let currentValue = Int(maxNText) ?? 1
        maxNText = "\(max(1, currentValue + delta))"
        saveMaxNOverride()
    }

    private func saveMaxNOverride() {
        guard let project = viewModel.fetchProject(projectID, modelContext: modelContext),
              viewModel.canEditMaxN(project: project) else { return }
        let trimmed = maxNText.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? nil : max(1, Int(trimmed) ?? 1)
        maxNText = value.map(String.init) ?? ""
        do {
            try viewModel.saveMaxNOverride(value, project: project, modelContext: modelContext)
            decisionVersion += 1
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func saveSpeciesSelection(_ selection: SpeciesSelection, replacingID selectionID: String?, project: Project) {
        do {
            try viewModel.saveSpeciesSelection(
                selection,
                replacingID: selectionID,
                project: project,
                modelContext: modelContext
            )
            decisionVersion += 1
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func deleteSpeciesSelection(_ selection: SpeciesSelection, project: Project) {
        do {
            try viewModel.deleteSpeciesSelection(selection, project: project, modelContext: modelContext)
            decisionVersion += 1
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func saveSpeciesDrafts(_ drafts: [SpeciesAssignmentDraft], project: Project) {
        do {
            for draft in drafts {
                try viewModel.saveSpeciesAssignment(
                    draft,
                    project: project,
                    modelContext: modelContext
                )
            }
            decisionVersion += 1
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func speciesAssignmentDrafts(
        for selectedFile: ProjectScanFile,
        project: Project
    ) -> [SpeciesAssignmentDraft] {
        viewModel.speciesAssignmentDrafts(for: selectedFile, project: project, modelContext: modelContext)
    }

    private func setDetectionRemoved(_ isRemoved: Bool, project: Project) {
        do {
            try viewModel.setRemovedFromExport(isRemoved, project: project, modelContext: modelContext)
            decisionVersion += 1
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
    
    private func movePrevious(project: Project) {
        saveMaxNOverride()
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.movePrevious(project: project)
        }
    }
    
    private func moveNext(project: Project) {
        saveMaxNOverride()
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.moveNext(project: project)
        }
    }

    private func finishAudit(project: Project) {
        coordinator.goToNextStep(for: project)
    }

    private func currentDecision(for file: ProjectScanFile, project: Project) -> ManualAuditDecisionValue? {
        pendingDecisions[file.relativePath] ?? viewModel.decision(
            for: file,
            project: project,
            modelContext: modelContext,
            version: decisionVersion
        )
    }

}
