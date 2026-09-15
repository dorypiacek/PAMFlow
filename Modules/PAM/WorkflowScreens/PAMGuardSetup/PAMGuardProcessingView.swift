//
//  PAMGuardProcessingView.swift
//  PAMFlow
//
//  Created by Dory on 03/07/2026.
//

import SwiftData
import UI
import Core
import SwiftUI

/// Renders PAMGuard import progress while its ViewModel owns detection processing.
struct PAMGuardProcessingView: View {
    @Environment(\.modelContext) private var modelContext

    let projectID: UUID
    let projectScanService: ProjectScanServicing
    let processingService: PAMGuardDetectionProcessingServicing
    let workflowActions: WorkflowActionHandling

    @State private var viewModel: PAMGuardProcessingViewModel

    init(
        projectID: UUID,
        projectScanService: ProjectScanServicing,
        processingService: PAMGuardDetectionProcessingServicing,
        workflowActions: WorkflowActionHandling
    ) {
        self.projectID = projectID
        self.projectScanService = projectScanService
        self.processingService = processingService
        self.workflowActions = workflowActions
        _viewModel = State(
            initialValue: PAMGuardProcessingViewModel(
                projectID: projectID,
                projectScanService: projectScanService,
                processingService: processingService
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    LoadingCardView(
                        title: PAMStrings.Processing.title,
                        subtitle: PAMStrings.Processing.subtitle,
                        message: viewModel.message,
                        progress: viewModel.progress,
                        errorMessage: viewModel.errorMessage
                    ) {
                        if viewModel.errorMessage != nil {
                            if let project = viewModel.fetchProject(modelContext: modelContext) {
                                Button(PAMStrings.Processing.retry) {
                                    viewModel.start(project: project, modelContext: modelContext, workflowActions: workflowActions)
                                }
                                .buttonStyle(.primaryAction)
                            }
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
            viewModel.startIfNeeded(modelContext: modelContext, workflowActions: workflowActions)
        }
    }
}
