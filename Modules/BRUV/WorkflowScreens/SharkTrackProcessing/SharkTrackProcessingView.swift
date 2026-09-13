//
//  SharkTrackProcessingView.swift
//  PAMFlow
//
//  Created by Dory on 19/06/2026.
//

import SwiftData
import SwiftUI

/// Renders BRUV/RUV SharkTrack progress while its ViewModel owns processing state.
///
/// This screen intentionally mirrors the scan progress screen so processing is
/// presented as a durable workflow step instead of a side effect of the project
/// overview.
struct SharkTrackProcessingView: View {
    @Environment(\.modelContext) private var modelContext

    let projectID: UUID
    let workflowActions: WorkflowActionHandling

    @State private var viewModel: SharkTrackProcessingViewModel

    init(
        projectID: UUID,
        workflowActions: WorkflowActionHandling,
        sharkTrackService: SharkTrackServicing,
        projectScanService: ProjectScanServicing
    ) {
        self.projectID = projectID
        self.workflowActions = workflowActions
        _viewModel = State(initialValue: SharkTrackProcessingViewModel(
            projectID: projectID,
            sharkTrackService: sharkTrackService,
            projectScanService: projectScanService
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    LoadingCardView(
                        title: BRUVStrings.Processing.title,
                        subtitle: BRUVStrings.Processing.subtitle,
                        message: viewModel.statusMessage,
                        progress: viewModel.progress,
                        detail: viewModel.detailMessage,
                        errorMessage: viewModel.errorMessage
                    ) {
                        if viewModel.errorMessage != nil {
                            Button(BRUVStrings.Processing.retryButton) {
                                Task {
                                    await viewModel.processProject(modelContext: modelContext, workflowActions: workflowActions)
                                }
                            }
                            .buttonStyle(.primaryAction)
                        }
                    }
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task {
            await viewModel.processProject(modelContext: modelContext, workflowActions: workflowActions)
        }
        .task(id: viewModel.isProcessing) {
            guard viewModel.isProcessing else { return }
            await viewModel.runProgressHeartbeat()
        }
    }
}
