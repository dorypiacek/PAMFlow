//
//  ManualAuditOverviewView.swift
//  PAMFlow
//
//  Created by Dory on 17/06/2026.
//

import SwiftData
import SwiftUI

/// Renders manual-audit summary state and forwards workflow actions to its ViewModel.
struct ManualAuditOverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID
    let projectScanService: ProjectScanServicing

    @State private var viewModel: ManualAuditOverviewViewModel
    @State private var isSpeciesExpanded = true
    @State private var isMediaBreakdownExpanded = false

    init(projectID: UUID, projectScanService: ProjectScanServicing) {
        self.projectID = projectID
        self.projectScanService = projectScanService
        _viewModel = State(initialValue: ManualAuditOverviewViewModel(
            projectID: projectID,
            projectScanService: projectScanService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            ScrollView {
                let overview = viewModel.overviewModel(modelContext: modelContext)
                VStack(alignment: .leading, spacing: Spacing.large) {
                    header(
                        title: overview?.title ?? Strings.ManualAuditOverview.title,
                        subtitle: overview?.subtitle ?? Strings.ManualAuditOverview.subtitle
                    )

                    if let presentation = overview {
                        overviewContent(presentation)
                    } else if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(AppColors.error)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(Spacing.large)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(AppColors.background)
        .task {
            viewModel.load(modelContext: modelContext)
        }
    }

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(title)
                .font(Fonts.screenTitle)

            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func overviewContent(_ presentation: ManualAuditOverviewPresentation) -> some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            HighlightBlockView(
                count: "\(presentation.reviewedCount)",
                title: String(format: Strings.ManualAuditOverview.reviewedTitleFormat, presentation.totalCount),
                metrics: [
                    HighlightMetric(Strings.ManualAuditOverview.project, presentation.project.name),
                    HighlightMetric(Strings.ManualAuditOverview.valid, "\(presentation.validCount)", valueColor: AppColors.success),
                    HighlightMetric(Strings.ManualAuditOverview.invalid, "\(presentation.invalidCount)", valueColor: presentation.invalidCount == 0 ? .primary : AppColors.error),
                    HighlightMetric(Strings.ManualAuditOverview.remaining, "\(presentation.remainingCount)"),
                    HighlightMetric(
                        presentation.readyMetricTitle,
                        presentation.readyMetricValue,
                        valueColor: presentation.isComplete ? AppColors.success : AppColors.error
                    )
                ]
            )

            overviewDetails(presentation)

            if presentation.totalCount == 0 {
                Text(Strings.ManualAuditOverview.noReviewFramesCreated)
                    .font(Fonts.body)
                    .foregroundStyle(.secondary)
                    .padding(Spacing.medium)
                    .glassySurface()
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Metrics.Layout.auditOverviewRowWidth), spacing: Spacing.large, alignment: .top)],
                alignment: .leading,
                spacing: Spacing.large
            ) {
                if presentation.isPAMGuardDetectionReview {
                    speciesBreakdown(presentation.speciesRows, isExpanded: $isSpeciesExpanded)
                    countBreakdown(
                        title: Strings.ManualAuditOverview.detectionsByRecording,
                        rows: presentation.audioRecordingRows,
                        isExpanded: $isMediaBreakdownExpanded
                    )
                } else if presentation.module.requiresSharkTrack {
                    speciesBreakdown(presentation.speciesRows, isExpanded: $isSpeciesExpanded)
                    countBreakdown(
                        title: Strings.ManualAuditOverview.detectionsByVideo,
                        rows: presentation.mediaBreakdownRows,
                        isExpanded: $isMediaBreakdownExpanded
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Button(Strings.ManualAuditOverview.backToAudit) {
                    appCoordinator.goToNextStep(for: presentation.project, startAtLastReviewed: true)
                }
                .buttonStyle(.secondaryAction)

                Button(presentation.primaryActionTitle) {
                    completePrimaryAction(presentation)
                }
                .buttonStyle(.primaryAction)
                .help(presentation.primaryActionHelp)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func overviewDetails(_ presentation: ManualAuditOverviewPresentation) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220), spacing: Spacing.medium, alignment: .leading)],
            alignment: .leading,
            spacing: Spacing.medium
        ) {
            ForEach(presentation.detailMetrics) { metric in
                compactMetric(metric.title, metric.value)
            }
        }
        .padding(Spacing.medium)
        .glassySurface()
    }

    /// Renders a grouped count card using rows already calculated by the snapshot.
    private func countBreakdown(
        title: String,
        rows: [ManualAuditOverviewPresentation.CountRow],
        isExpanded: Binding<Bool>
    ) -> some View {
        return expandableRowsCard(
            title: title,
            isExpanded: isExpanded,
            rowCount: rows.count
        ) {
            ForEach(displayedRows(rows, isExpanded: isExpanded.wrappedValue)) { row in
                HStack {
                    Text(row.name)
                        .lineLimit(1)
                    Spacer()
                    Text(row.progressText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: Metrics.Layout.auditOverviewRowWidth)
            }
        }
    }

    /// Renders species counts that were calculated outside the view.
    private func speciesBreakdown(_ rows: [ManualAuditOverviewPresentation.SpeciesRow], isExpanded: Binding<Bool>) -> some View {
        return expandableRowsCard(
            title: Strings.ManualAuditOverview.speciesCounts,
            isExpanded: isExpanded,
            rowCount: rows.count
        ) {
            if rows.isEmpty {
                Text(Strings.ManualAuditOverview.noSpeciesSelected)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedRows(rows, isExpanded: isExpanded.wrappedValue)) { item in
                    HStack {
                        Text(item.species)
                        Spacer()
                        Text("\(item.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: Metrics.Layout.auditOverviewRowWidth)
                }
            }
        }
    }

    private func expandableRowsCard<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        rowCount: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Text(title)
                    .font(Fonts.body.bold())
                Spacer()
                if rowCount > 3 {
                    Button(isExpanded.wrappedValue ? Strings.ManualAuditOverview.showLess : Strings.ManualAuditOverview.showAll) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.wrappedValue.toggle()
                        }
                    }
                    .buttonStyle(.secondaryAction)
                    .controlSize(.small)
                }
            }

            content()
        }
        .padding(Spacing.medium)
        .frame(minHeight: Metrics.Layout.auditOverviewCardHeight, alignment: .topLeading)
        .glassySurface()
    }

    private func displayedRows<Row>(_ rows: [Row], isExpanded: Bool) -> [Row] {
        rowLimit(for: rows.count, isExpanded: isExpanded).map { rows[$0] }
    }

    private func rowLimit(for count: Int, isExpanded: Bool) -> Range<Int> {
        0..<min(isExpanded || count <= 3 ? count : 3, count)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.auditOverviewCardHeight, alignment: .leading)
        .glassySurface()
    }

    private func compactMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func completePrimaryAction(_ presentation: ManualAuditOverviewPresentation) {
        do {
            try viewModel.completePrimaryAction(
                modelContext: modelContext,
                overview: presentation,
                coordinator: appCoordinator
            )
        } catch {
            viewModel.load(modelContext: modelContext)
        }
    }
}
