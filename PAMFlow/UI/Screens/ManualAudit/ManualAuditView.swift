//
//  ManualAuditView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import AppKit
import SwiftData
import SwiftUI

/// Renders manual review controls while `ManualAuditViewModel` owns queue state and decisions.
struct ManualAuditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator
    
    let projectID: UUID
    let startAtLastReviewed: Bool
    
    @State private var viewModel: ManualAuditViewModel
    @StateObject private var playbackService = AudioPlaybackService()
    @State private var decisionVersion = 0
    @State private var isShowingSpeciesSelection = false
    @State private var isShowingReasonSelection = false
    @State private var pendingDecisions: [String: ManualAuditDecisionValue] = [:]
    @State private var invalidReason = ""
    @State private var maxNText = ""

    init(
        projectID: UUID,
        startAtLastReviewed: Bool = false,
        projectScanService: ProjectScanServicing,
        audioPreviewCacheService: AudioPreviewCacheServicing
    ) {
        self.projectID = projectID
        self.startAtLastReviewed = startAtLastReviewed
        _viewModel = State(initialValue: ManualAuditViewModel(
            projectScanService: projectScanService,
            audioPreviewCacheService: audioPreviewCacheService
        ))
    }
    
    var body: some View {
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
            playbackService.stop()
            viewModel.cancelPreviewWork()
        }
        .sheet(isPresented: $isShowingSpeciesSelection) {
            if let project = viewModel.fetchProject(projectID, modelContext: modelContext), let file = viewModel.selectedFile {
                SpeciesSelectionSheet(
                    taxa: SpeciesCatalog.taxa(for: project.moduleID),
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
                        previewPanel(file: file, project: project)
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
                    syncInvalidReason(file: file, project: project)
                    syncMaxN(file: file, project: project)
                }
                .onChange(of: file.relativePath) { _, _ in
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
                Text(reviewTitle(for: project))
                    .font(Fonts.screenTitle)
                
                Text(viewModel.reviewHeaderText(
                    projectName: project.name,
                    module: WorkflowModule.module(for: project.moduleID)
                ))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
    
    private func previewPanel(file: ProjectScanFile, project: Project) -> some View {
        let module = WorkflowModule.module(for: project.moduleID)

        return VStack(alignment: .leading, spacing: Spacing.medium) {
            if module.requiresSharkTrack {
                sharkTrackPreview(file: file, project: project)
            } else if viewModel.isLoadingPreview {
                VStack(spacing: Spacing.small) {
                    ProgressView()
                    Text(Strings.ManualAudit.loadingPreview)
                        .font(Fonts.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else if let preview = viewModel.preview {
                previewImages(preview)
            } else {
                Text(viewModel.errorMessage ?? Strings.ManualAudit.previewUnavailable)
                    .foregroundStyle(AppColors.error)
                    .frame(maxHeight: .infinity, alignment: .center)
            }

            if module == .pamAudio {
                audioControls(file: file, project: project)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func sharkTrackPreview(file: ProjectScanFile, project: Project) -> some View {
        Group {
            if let image = viewModel.sharkTrackImage(file: file, project: project) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.Layout.rowCornerRadius))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(Strings.ManualAudit.previewUnavailable)
                    .foregroundStyle(AppColors.error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
    
    private func previewImages(_ preview: AudioPreview) -> some View {
        GeometryReader { proxy in
            let availableHeight = max(1, proxy.size.height - Spacing.small)
            let plotContainerHeight = max(1, availableHeight / 2)
            
            VStack(spacing: Spacing.small) {
                ChartWithPlayhead(
                    durationSeconds: preview.durationSeconds,
                    playbackService: playbackService
                ) {
                    WaveformView(
                        peaks: preview.waveformPeaks,
                        durationSeconds: preview.durationSeconds
                    )
                }
                .frame(height: plotContainerHeight)
                
                ChartWithPlayhead(
                    durationSeconds: preview.durationSeconds,
                    playbackService: playbackService
                ) {
                    SpectrogramView(
                        bins: preview.spectrogramBins,
                        durationSeconds: preview.durationSeconds,
                        maxFrequencyHz: preview.spectrogramMaxFrequencyHz
                    )
                }
                .frame(height: plotContainerHeight)
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    private func audioControls(file: ProjectScanFile, project: Project) -> some View {
        GeometryReader { proxy in
            let plot = chartPlotRect(proxy.size)
            let remainingWidth = Metrics.Layout.audioTimeLabelWidth
            let rowHeight = Metrics.Layout.auditControlHeight
            let buttonSize = Metrics.Layout.audioTransportButtonSize
            let controlSpacing = max(0, plot.minX - buttonSize)
            
            ZStack(alignment: .leading) {
                Button {
                    play(file: file, project: project)
                } label: {
                    Image(systemName: playbackService.isPlaying ? Icons.pause : Icons.play)
                        .font(.system(size: Metrics.Layout.audioButtonIconSize * 0.72, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(
                            width: buttonSize,
                            height: buttonSize
                        )
                        .background(AppColors.accent, in: Circle())
                }
                .help(playbackService.isPlaying ? Strings.ManualAudit.pauseHelp : Strings.ManualAudit.playHelp)
                .buttonStyle(.plain)
                .disabled(viewModel.audioURL(project: project, file: file) == nil)
                .frame(width: buttonSize, height: rowHeight, alignment: .center)
                
                TimelineView(.animation) { timeline in
                    let playbackPosition = playbackService.displayTime(at: timeline.date)
                    
                    ZStack(alignment: .leading) {
                        AudioScrubber(
                            currentTime: playbackPosition,
                            duration: playbackService.duration,
                            onDragStart: playbackService.pause,
                            onSeek: playbackService.seek(to:)
                        )
                        .frame(width: plot.width, height: rowHeight, alignment: .center)
                        .offset(x: plot.minX)
                        
                        Text(remainingPlaybackTime(playbackPosition, duration: playbackService.duration))
                            .font(Fonts.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: remainingWidth, alignment: .leading)
                            .offset(x: plot.maxX + controlSpacing)
                    }
                    .frame(width: proxy.size.width, height: rowHeight, alignment: .leading)
                }
                .frame(width: proxy.size.width, height: rowHeight, alignment: .leading)
            }
            .frame(width: proxy.size.width, height: rowHeight, alignment: .leading)
        }
        .frame(height: Metrics.Layout.auditControlHeight)
        .onAppear {
            preparePlayback(file: file, project: project)
        }
        .onChange(of: file.relativePath) {
            playbackService.stop()
            preparePlayback(file: file, project: project)
        }
    }
    
    private func evidencePanel(file: ProjectScanFile, project: Project) -> some View {
        let currentDecision = currentDecision(for: file, project: project)
        let module = WorkflowModule.module(for: project.moduleID)

        return VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(Strings.ManualAudit.scanEvidence)
                .font(Fonts.subtitle)
            
            metric(Strings.ManualAudit.fileName, displaySourceName(for: file, module: module))
            metric(Strings.ManualAudit.decision, currentDecision?.title ?? Strings.ManualAudit.notReviewed)
            if !viewModel.isPAMGuardDetectionReview(project: project) {
                metric(
                    Strings.ManualAudit.quality,
                    file.qualityFlag,
                    valueColor: qualityValueColor(file.qualityFlag)
                )
            }

        if module.requiresSharkTrack {
            sharkTrackEvidence(file, module: module)
        } else if viewModel.isPAMGuardDetectionReview(project: project) {
            pamguardDetectionEvidence(file)
        } else {
            audioEvidence(file)
        }
        }
    }

    @ViewBuilder
    private func sharkTrackEvidence(_ file: ProjectScanFile, module: WorkflowModule) -> some View {
        if let trackID = file.trackID {
            metric(Strings.ManualAudit.trackID, "\(trackID)")
        }
        if let confidence = file.sharkTrackConfidence {
            metric(Strings.ManualAudit.confidence, confidence.formatted(.percent.precision(.fractionLength(0))))
        }
        if let frameNumber = file.frameNumber {
            metric(Strings.ManualAudit.frameNumber, "\(frameNumber)")
        }
        editableMaxNMetric(file: file)
        if let width = file.width, let height = file.height {
            metric(Strings.ManualAudit.imageSize, "\(width) x \(height)")
        }
        if let format = file.format {
            metric(Strings.ManualAudit.format, format)
        }
        metric(Strings.ManualAudit.fileSize, formattedFileSize(file.sizeBytes))
        if let sharkTrackStatus = file.sharkTrackStatus {
            metric(Strings.ManualAudit.sharkTrackStatus, sharkTrackStatus.capitalized)
        }
    }

    @ViewBuilder
    private func audioEvidence(_ file: ProjectScanFile) -> some View {
        metric(Strings.ManualAudit.duration, file.durationSeconds.map(formatDuration) ?? Strings.Common.unknown)
        metric(Strings.ManualAudit.sampleRate, file.sampleRateHz.map { "\($0) Hz" } ?? Strings.Common.unknown)
        metric(Strings.ManualAudit.channels, file.channels.map(String.init) ?? Strings.Common.unknown)
        metric(Strings.ManualAudit.bitDepth, file.bitDepth.map { "\($0) bit" } ?? Strings.Common.unknown)
        metric(Strings.ManualAudit.peak, file.peakDBFS.map { String(format: "%.1f dBFS", $0) } ?? Strings.Common.unknown)
        metric(Strings.ManualAudit.rms, file.rmsDBFS.map { String(format: "%.1f dBFS", $0) } ?? Strings.Common.unknown)
        metric(Strings.ManualAudit.clipping, file.clippingPercent.map { String(format: "%.3f%%", $0) } ?? Strings.Common.unknown)
        metric(Strings.ManualAudit.nearZero, file.nearZeroPercent.map { String(format: "%.1f%%", $0) } ?? Strings.Common.unknown)
    }

    @ViewBuilder
    private func pamguardDetectionEvidence(_ file: ProjectScanFile) -> some View {
        metric(Strings.ManualAudit.detectionID, detectionIdentifier(for: file))
        metric(Strings.ManualAudit.startTime, metadataValue(file, key: Strings.ManualAudit.startTime))
        metric(Strings.ManualAudit.endTime, metadataValue(file, key: Strings.ManualAudit.endTime))
        metric(Strings.ManualAudit.format, file.format ?? Strings.Common.unknown)
        metric(Strings.ManualAudit.duration, file.durationSeconds.map(formatDuration) ?? Strings.Common.unknown)
        if let confidence = file.sharkTrackConfidence {
            metric(Strings.ManualAudit.confidence, confidence.formatted(.number.precision(.fractionLength(2))))
        }
    }
    
    private func decisionControls(project: Project) -> some View {
        let selectedDecision: ManualAuditDecisionValue?
        if let selectedFile = viewModel.selectedFile {
            selectedDecision = currentDecision(for: selectedFile, project: project)
        } else {
            selectedDecision = nil
        }
        let requiresInvalidReason = viewModel.reasonConfiguration(for: project).isRequired && selectedDecision == .invalid
        let canNavigate = selectedDecision != nil && (!requiresInvalidReason || !invalidReason.isEmpty)
        let module = WorkflowModule.module(for: project.moduleID)
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
                ForEach(decisionOptions(for: module), id: \.self) { decision in
                    decisionButton(
                        decision,
                        isSelected: selectedDecision == decision,
                        project: project
                    )
                }

                if shouldShowReviewAction(for: module, project: project) {
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
        .animation(.smooth, value: selectedDecision)
    }

    private func decisionOptions(for module: WorkflowModule) -> [ManualAuditDecisionValue] {
        if module == .pamAudio,
           let project = viewModel.fetchProject(projectID, modelContext: modelContext),
           viewModel.isPAMGuardDetectionReview(project: project) {
            return [.valid, .unsure, .invalid]
        }
        return module == .pamAudio ? [.valid, .unsure, .invalid] : [.valid, .invalid]
    }

    @ViewBuilder
    private func detectionActionButton(
        selectedDecision: ManualAuditDecisionValue?,
        project: Project,
        canNavigate: Bool
    ) -> some View {
        let module = WorkflowModule.module(for: project.moduleID)
        let canAssignSpecies = module.requiresSharkTrack
        if selectedDecision == .valid, canAssignSpecies {
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
        if isSelected {
            Button {
                save(decision, project: project)
            } label: {
                decisionLabel(decision, isSelected: true)
            }
            .buttonStyle(.primaryAction)
            .controlSize(.regular)
            .tint(AppColors.accent)
            .frame(minWidth: Metrics.Layout.decisionButtonMinWidth)
            .clipShape(.capsule)
        } else {
            Button {
                save(decision, project: project)
            } label: {
                decisionLabel(decision, isSelected: false)
            }
            .buttonStyle(.prominentSecondaryAction)
            .controlSize(.regular)
            .frame(minWidth: Metrics.Layout.decisionButtonMinWidth)
            .clipShape(.capsule)
        }
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
                    Image(systemName: "minus")
                }
                .buttonStyle(.iconAction)
                .disabled((Int(maxNText) ?? file.maxN ?? 1) <= 1)

                TextField(file.maxN.map(String.init) ?? "1", text: $maxNText)
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
                    Image(systemName: "plus")
                }
                .buttonStyle(.iconAction)
            }
        }
    }

    private func qualityValueColor(_ flag: String) -> Color {
        flag.localizedCaseInsensitiveCompare("OK") == .orderedSame ? .primary : AppColors.error
    }

    private func displaySourceName(for file: ProjectScanFile, module: WorkflowModule) -> String {
        guard module.requiresSharkTrack else {
            return file.sourceVideo ?? file.fileName
        }
        if let sourceVideo = file.sourceVideo, !sourceVideo.isEmpty {
            return sourceVideo
        }

        let components = file.relativePath.split(separator: "/").map(String.init)
        if let internalResultsIndex = components.firstIndex(of: "internal_results"),
           components.indices.contains(internalResultsIndex + 1) {
            return components[internalResultsIndex + 1]
        }

        return isSharkTrackOutputName(file.fileName) ? Strings.Common.unknown : file.fileName
    }

    private func isSharkTrackOutputName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("elasmobranch") || lowercased.contains("sharktrack")
    }
    
    private func play(file: ProjectScanFile, project: Project) {
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio,
              let inputFolderURL = project.inputFolderURL else { return }
        
        let url = inputFolderURL.appendingPathComponent(file.sourceVideo ?? file.relativePath)
        
        do {
            try playbackService.togglePlayback(
                url: url,
                securityScopedURL: inputFolderURL,
                clipStartSeconds: viewModel.clipStartSeconds(project: project, file: file),
                clipDurationSeconds: viewModel.clipDurationSeconds(project: project, file: file)
            )
            viewModel.errorMessage = nil
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
    
    private func preparePlayback(file: ProjectScanFile?, project: Project) {
        guard WorkflowModule.module(for: project.moduleID) == .pamAudio,
              let file,
              let inputFolderURL = project.inputFolderURL else {
            return
        }
        
        playbackService.prepareIfNeeded(
            url: inputFolderURL.appendingPathComponent(file.sourceVideo ?? file.relativePath),
            securityScopedURL: inputFolderURL,
            clipStartSeconds: viewModel.clipStartSeconds(project: project, file: file),
            clipDurationSeconds: viewModel.clipDurationSeconds(project: project, file: file)
        )
    }
    
    private func save(_ decision: ManualAuditDecisionValue, project: Project) {
        guard let file = viewModel.selectedFile else { return }
        pendingDecisions[file.relativePath] = decision
        decisionVersion += 1

        do {
            try viewModel.saveDecision(decision, project: project, modelContext: modelContext)
            saveMaxNOverride()
            if decision == .invalid || decision == .unsure {
                viewModel.saveInvalidReason(invalidReason, project: project, modelContext: modelContext)
            } else {
                invalidReason = ""
                viewModel.saveInvalidReason(invalidReason, project: project, modelContext: modelContext)
            }
            decisionVersion += 1
        } catch {
            pendingDecisions[file.relativePath] = nil
            decisionVersion += 1
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func setInvalidReason(_ reason: String, project: Project) {
        invalidReason = reason
        viewModel.saveInvalidReason(reason, project: project, modelContext: modelContext)
        decisionVersion += 1
    }

    private func shouldShowReviewAction(for module: WorkflowModule, project: Project) -> Bool {
        module.requiresSharkTrack ||
            module == .pamAudio
    }

    private func detectionIdentifier(for file: ProjectScanFile) -> String {
        if let trackID = file.trackID {
            return "\(trackID)"
        }

        return file.relativePath
            .replacingOccurrences(of: "pamguard/events/", with: "")
            .replacingOccurrences(of: "pamguard/detections/", with: "")
            .replacingOccurrences(of: ".png", with: "")
    }

    private func metadataValue(_ file: ProjectScanFile, key: String) -> String {
        let prefix = "\(key):"
        return file.qualityReasons
            .first { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? Strings.Common.unknown
    }

    private func syncInvalidReason(file: ProjectScanFile, project: Project) {
        invalidReason = viewModel.auditDecision(for: file, project: project, modelContext: modelContext)?.notes ?? ""
    }

    private func syncMaxN(file: ProjectScanFile, project: Project) {
        maxNText = viewModel.effectiveMaxN(for: file, project: project, modelContext: modelContext).map(String.init) ?? ""
    }

    private func adjustMaxN(by delta: Int) {
        let currentValue = Int(maxNText) ?? viewModel.selectedFile?.maxN ?? 1
        maxNText = "\(max(1, currentValue + delta))"
        saveMaxNOverride()
    }

    private func saveMaxNOverride() {
        guard let project = viewModel.fetchProject(projectID, modelContext: modelContext),
              WorkflowModule.module(for: project.moduleID).requiresSharkTrack else { return }
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
        viewModel.detectionsInCurrentFrame(for: selectedFile).map { file in
            SpeciesAssignmentDraft(
                id: file.relativePath,
                trackID: file.trackID,
                confidence: file.sharkTrackConfidence,
                selection: viewModel.speciesSelections(
                    for: file,
                    project: project,
                    modelContext: modelContext
                ).first,
                isRemoved: viewModel.isRemovedFromExport(
                    for: file,
                    project: project,
                    modelContext: modelContext
                )
            )
        }
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
        playbackService.stop()
        saveMaxNOverride()
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.movePrevious(project: project)
        }
    }
    
    private func moveNext(project: Project) {
        playbackService.stop()
        saveMaxNOverride()
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.moveNext(project: project)
        }
    }

    private func finishAudit(project: Project) {
        playbackService.stop()
        appCoordinator.goToNextStep(for: project)
    }

    private func currentDecision(for file: ProjectScanFile, project: Project) -> ManualAuditDecisionValue? {
        pendingDecisions[file.relativePath] ?? viewModel.decision(
            for: file,
            project: project,
            modelContext: modelContext,
            version: decisionVersion
        )
    }

    private func reviewTitle(for project: Project) -> String {
        viewModel.isPAMGuardDetectionReview(project: project)
            ? Strings.ManualAudit.detectionReviewTitle
            : WorkflowModule.module(for: project.moduleID).requiresSharkTrack
            ? Strings.ManualAudit.frameReviewTitle
            : Strings.ManualAudit.title
    }

    
    private func formatDuration(_ seconds: Double) -> String {
        seconds >= 60 ? "\(Int(seconds.rounded())) seconds" : String(format: "%.1f seconds", seconds)
    }

    private func formattedFileSize(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
    
    private func formatPlaybackTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        
        let totalSeconds = Int(seconds.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }
    
    private func remainingPlaybackTime(_ currentTime: Double, duration: Double) -> String {
        let remaining = max(duration - currentTime, 0)
        return "-\(formatPlaybackTime(remaining))"
    }
    
}

private struct WaveformView: View {
    let peaks: [WaveformPeak]
    let durationSeconds: Double
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Canvas { context, size in
            guard peaks.count > 1 else { return }
            
            let plot = chartPlotRect(size)
            let midY = plot.midY
            let xStep = plot.width / CGFloat(max(1, peaks.count - 1))
            let scale = plot.height / 2
            
            drawAxes(context: context, plot: plot, size: size)
            
            var upper = Path()
            var lowerPoints: [CGPoint] = []
            for index in peaks.indices {
                let x = plot.minX + CGFloat(index) * xStep
                let minY = midY - CGFloat(peaks[index].minimum) * scale
                let maxY = midY - CGFloat(peaks[index].maximum) * scale
                let upperPoint = CGPoint(x: x, y: maxY)
                let lowerPoint = CGPoint(x: x, y: minY)
                if index == peaks.startIndex {
                    upper.move(to: upperPoint)
                } else {
                    upper.addLine(to: upperPoint)
                }
                lowerPoints.append(lowerPoint)
            }

            for point in lowerPoints.reversed() {
                upper.addLine(to: point)
            }
            upper.closeSubpath()

            context.fill(upper, with: .color(Color(red: 0.12, green: 0.47, blue: 0.71)))
            context.stroke(upper, with: .color(Color(red: 0.12, green: 0.47, blue: 0.71)), lineWidth: 1)
        }
    }
    
    private func drawAxes(context: GraphicsContext, plot: CGRect, size: CGSize) {
        var background = Path()
        background.addRect(plot)
        context.fill(background, with: .color(waveformPlotBackground(colorScheme)))

        for value in [-1.0, -0.5, 0, 0.5, 1.0] {
            let y = plot.midY - CGFloat(value) * plot.height / 2
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(chartGridColor(colorScheme).opacity(value == 0 ? 0.22 : 0.10)), lineWidth: 1)
        }

        var border = Path()
        border.addRect(plot)
        context.stroke(border, with: .color(chartAxisColor(colorScheme)), lineWidth: 1)
        
        drawText(context, Strings.ManualAudit.amplitude, CGPoint(x: plot.minX, y: plot.minY - 22), color: chartLabelColor(colorScheme))
        drawText(context, Strings.ManualAudit.timeAxis, CGPoint(x: plot.midX - 24, y: plot.maxY + 22), color: chartLabelColor(colorScheme))

        drawText(context, "1", CGPoint(x: 0, y: plot.minY - 6), color: chartLabelColor(colorScheme))
        drawText(context, "0", CGPoint(x: 0, y: plot.midY - 6), color: chartLabelColor(colorScheme))
        drawText(context, "-1", CGPoint(x: 0, y: plot.maxY - 10), color: chartLabelColor(colorScheme))
        
        for tick in timeTicks(duration: durationSeconds) {
            let x = plot.minX + plot.width * CGFloat(tick / max(durationSeconds, 0.01))
            drawText(context, "\(Int(tick))", CGPoint(x: x - 4, y: plot.maxY + 6), color: chartLabelColor(colorScheme))
        }
    }
    
}

private struct SpectrogramView: View {
    let bins: [[Float]]
    let durationSeconds: Double
    let maxFrequencyHz: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    
    var body: some View {
        Canvas { context, size in
            guard let firstColumn = bins.first, !firstColumn.isEmpty else { return }

            let plot = chartPlotRect(size)
            let maxFrequency = max(maxFrequencyHz, 1)
            var background = Path()
            background.addRect(plot)
            context.fill(background, with: .color(spectrogramPlotBackground))

            var plotContext = context
            plotContext.clip(to: Path(plot))
            let rasterScale = max(displayScale, 1)
            let sampleColumns = max(1, min(Int((plot.width * rasterScale).rounded(.up)), bins.count))
            let sampleRows = max(1, min(Int((plot.height * rasterScale).rounded(.up)), firstColumn.count))
            let cellWidth = plot.width / CGFloat(sampleColumns)
            let cellHeight = plot.height / CGFloat(sampleRows)

            for xIndex in 0..<sampleColumns {
                let x = plot.minX + CGFloat(xIndex) * cellWidth

                for yIndex in 0..<sampleRows {
                    let value = rasterValue(
                        xIndex: xIndex,
                        yIndex: yIndex,
                        rasterColumns: sampleColumns,
                        rasterRows: sampleRows
                    )
                    let y = plot.maxY - CGFloat(yIndex + 1) * cellHeight
                    let rect = CGRect(
                        x: x,
                        y: y,
                        width: cellWidth + 0.75,
                        height: cellHeight + 0.75
                    ).intersection(plot)
                    guard !rect.isNull, rect.width > 0, rect.height > 0 else { continue }
                    plotContext.fill(Path(rect), with: .color(color(for: value)))
                }
            }

            drawAxes(context: context, plot: plot, maxFrequency: maxFrequency)
        }
    }

    private func rasterValue(
        xIndex: Int,
        yIndex: Int,
        rasterColumns: Int,
        rasterRows: Int
    ) -> Double {
        guard let firstColumn = bins.first, !bins.isEmpty, !firstColumn.isEmpty else {
            return 0
        }

        let columnStart = Double(xIndex) / Double(max(rasterColumns, 1)) * Double(bins.count)
        let columnEnd = Double(xIndex + 1) / Double(max(rasterColumns, 1)) * Double(bins.count)
        let rowStart = Double(yIndex) / Double(max(rasterRows, 1)) * Double(firstColumn.count)
        let rowEnd = Double(yIndex + 1) / Double(max(rasterRows, 1)) * Double(firstColumn.count)

        if columnEnd - columnStart <= 1, rowEnd - rowStart <= 1 {
            let time = durationSeconds * (Double(xIndex) + 0.5) / Double(max(rasterColumns, 1))
            let frequency = maxFrequencyHz * (Double(yIndex) + 0.5) / Double(max(rasterRows, 1))
            return interpolatedValue(time: time, frequency: frequency)
        }

        let columnLower = min(bins.count - 1, max(0, Int(floor(columnStart))))
        let columnUpper = min(bins.count - 1, max(columnLower, Int(ceil(columnEnd)) - 1))
        let rowLower = min(firstColumn.count - 1, max(0, Int(floor(rowStart))))
        let rowUpper = min(firstColumn.count - 1, max(rowLower, Int(ceil(rowEnd)) - 1))
        var peak = 0.0

        for column in columnLower...columnUpper {
            var sum = 0.0
            var count = 0
            for row in rowLower...rowUpper {
                sum += valueAt(column: column, row: row)
                count += 1
            }
            if count > 0 {
                peak = max(peak, sum / Double(count))
            }
        }

        return peak
    }

    private func interpolatedValue(time: Double, frequency: Double) -> Double {
        guard let firstColumn = bins.first, !bins.isEmpty, !firstColumn.isEmpty else {
            return 0
        }

        let maxColumn = Double(bins.count - 1)
        let maxRow = Double(firstColumn.count - 1)
        let displayedMaxFrequency = max(maxFrequencyHz, 1)
        let columnPosition = min(max(time / max(durationSeconds, 0.01) * maxColumn, 0), maxColumn)
        let rowPosition = min(max(frequency / displayedMaxFrequency * maxRow, 0), maxRow)
        let column0 = Int(floor(columnPosition))
        let row0 = Int(floor(rowPosition))
        let column1 = min(column0 + 1, bins.count - 1)
        let row1 = min(row0 + 1, firstColumn.count - 1)
        let columnFraction = columnPosition - Double(column0)
        let rowFraction = rowPosition - Double(row0)
        let value00 = valueAt(column: column0, row: row0)
        let value10 = valueAt(column: column1, row: row0)
        let value01 = valueAt(column: column0, row: row1)
        let value11 = valueAt(column: column1, row: row1)
        let lower = value00 + (value10 - value00) * columnFraction
        let upper = value01 + (value11 - value01) * columnFraction
        return lower + (upper - lower) * rowFraction
    }

    private func valueAt(column: Int, row: Int) -> Double {
        guard bins.indices.contains(column), bins[column].indices.contains(row) else {
            return 0
        }
        return Double(bins[column][row])
    }
    
    private func color(for value: Double) -> Color {
        let stops: [(Double, Double, Double, Double)] = [
            (0.04, 0.02, 0.12, 1.00),
            (0.16, 0.05, 0.34, 1.00),
            (0.46, 0.08, 0.55, 1.00),
            (0.86, 0.24, 0.45, 1.00),
            (1.00, 0.55, 0.22, 1.00),
            (1.00, 0.92, 0.60, 1.00)
        ]
        let clamped = pow(min(1, max(0, value)), 0.55)
        let scaled = clamped * Double(stops.count - 1)
        let lower = min(Int(scaled), stops.count - 2)
        let fraction = scaled - Double(lower)
        let a = stops[lower]
        let b = stops[lower + 1]
        
        return Color(
            red: a.0 + (b.0 - a.0) * fraction,
            green: a.1 + (b.1 - a.1) * fraction,
            blue: a.2 + (b.2 - a.2) * fraction,
            opacity: a.3 + (b.3 - a.3) * fraction
        )
    }

    private func drawAxes(
        context: GraphicsContext,
        plot: CGRect,
        maxFrequency: Double
    ) {
        drawText(context, Strings.ManualAudit.frequencyAxis, CGPoint(x: plot.minX, y: plot.minY - 22), color: chartLabelColor(colorScheme))
        drawText(context, Strings.ManualAudit.timeAxis, CGPoint(x: plot.midX - 24, y: plot.maxY + 22), color: chartLabelColor(colorScheme))

        var border = Path()
        border.addRect(plot)
        context.stroke(border, with: .color(chartAxisColor(colorScheme)), lineWidth: 1)

        drawText(
            context,
            Strings.ManualAudit.displayRange,
            CGPoint(x: plot.minX + Spacing.small, y: plot.minY + Spacing.small),
            color: Color.black.opacity(0.86),
            background: Color.white.opacity(0.64)
        )
        
        for tick in frequencyTicks(maxFrequency: maxFrequency) {
            let y = plot.maxY - plot.height * CGFloat(tick / max(maxFrequency, 1))
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
            drawText(context, frequencyLabel(tick), CGPoint(x: 0, y: y - 7), color: chartLabelColor(colorScheme))
        }
        
        for tick in timeTicks(duration: durationSeconds) {
            let x = plot.minX + plot.width * CGFloat(tick / max(durationSeconds, 0.01))
            drawText(context, "\(Int(tick))", CGPoint(x: x - 4, y: plot.maxY + 6), color: chartLabelColor(colorScheme))
        }
    }
    
}

private struct ChartWithPlayhead<Content: View>: View {
    let durationSeconds: Double
    @ObservedObject var playbackService: AudioPlaybackService
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        ZStack {
            content()
            
            TimelineView(.animation) { timeline in
                PlayheadOverlay(
                    durationSeconds: durationSeconds,
                    playbackPosition: playbackService.displayTime(at: timeline.date)
                )
            }
        }
    }
}

private struct PlayheadOverlay: View {
    let durationSeconds: Double
    let playbackPosition: Double
    
    var body: some View {
        GeometryReader { proxy in
            let plot = chartPlotRect(proxy.size)
            let progress = durationSeconds > 0 ? min(max(playbackPosition / durationSeconds, 0), 1) : 0
            let x = plot.minX + plot.width * CGFloat(progress)
            
            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 1, height: plot.height)
                .position(x: x, y: plot.midY)
                .opacity(playbackPosition > 0 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

private struct AudioScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onDragStart: () -> Void
    let onSeek: (TimeInterval) -> Void
    
    @State private var isDragging = false
    @State private var dragFraction: Double = 0
    
    private var displayedFraction: Double {
        if isDragging {
            return dragFraction
        }
        
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    
    var body: some View {
        GeometryReader { proxy in
            let trackHeight = Metrics.Layout.scrubberTrackHeight
            let thumbSize = Metrics.Layout.scrubberThumbSize
            let width = max(1, proxy.size.width)
            let height = max(thumbSize, proxy.size.height)
            let thumbX = width * displayedFraction
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.14))
                    .frame(height: trackHeight)
                
                Capsule()
                    .fill(AppColors.accent)
                    .frame(width: max(0, thumbX), height: trackHeight)
                
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: min(max(thumbX - thumbSize / 2, 0), max(0, width - thumbSize)))
            }
            .frame(width: width, height: height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        if !isDragging {
                            onDragStart()
                        }
                        isDragging = true
                        dragFraction = fraction
                        onSeek(duration * fraction)
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        onSeek(duration * fraction)
                        dragFraction = fraction
                        isDragging = false
                    }
            )
        }
        .frame(height: 24, alignment: .center)
    }
}

private func drawText(
    _ context: GraphicsContext,
    _ text: String,
    _ point: CGPoint,
    color: Color,
    background: Color? = nil
) {
    let resolved = context.resolve(Text(text).font(.caption2).foregroundStyle(color))
    if let background {
        let size = resolved.measure(in: CGSize(width: 240, height: 40))
        context.fill(
            Path(CGRect(x: point.x - 4, y: point.y - 3, width: size.width + 8, height: size.height + 6)),
            with: .color(background)
        )
    }
    
    context.draw(resolved, at: point, anchor: .topLeading)
}

private let spectrogramPlotBackground = Color(red: 0.02, green: 0.01, blue: 0.06)

private func waveformPlotBackground(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark
        ? Color(red: 0.12, green: 0.16, blue: 0.17)
        : Color.white
}

private func chartAxisColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.72)
}

private func chartGridColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white : Color.black
}

private func chartLabelColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.86) : Color.black.opacity(0.84)
}

private func chartPlotRect(_ size: CGSize) -> CGRect {
    CGRect(
        x: Metrics.Layout.chartAxisLeadingInset,
        y: Metrics.Layout.chartTopInset,
        width: max(1, size.width - Metrics.Layout.chartAxisLeadingInset - Metrics.Layout.chartTrailingInset),
        height: max(1, size.height - Metrics.Layout.chartTopInset - Metrics.Layout.chartBottomInset)
    )
}

private func timeTicks(duration: Double) -> [Double] {
    guard duration > 0 else { return [] }
    let step = duration <= 10 ? 1.0 : duration <= 30 ? 5.0 : 10.0
    return stride(from: 0.0, through: duration, by: step).map { $0 }
}

private func frequencyTicks(maxFrequency: Double) -> [Double] {
    guard maxFrequency > 0 else { return [] }
    let step = maxFrequency >= 100_000 ? 50_000.0 : maxFrequency >= 40_000 ? 10_000.0 : 5_000.0
    var ticks = stride(from: 0.0, through: maxFrequency, by: step).map { $0 }
    if ticks.last.map({ abs($0 - maxFrequency) > step * 0.2 }) ?? true {
        ticks.append(maxFrequency)
    }
    return ticks
}

private func clampedFrequencyZoom(_ zoom: Double) -> Double {
    min(max(zoom, 1), 8)
}

private func frequencyLabel(_ frequency: Double) -> String {
    if frequency >= 1_000 {
        "\(Int(frequency / 1_000))k"
    } else {
        "\(Int(frequency))"
    }
}
