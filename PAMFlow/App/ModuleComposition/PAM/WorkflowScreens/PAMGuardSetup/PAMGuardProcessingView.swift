//
//  PAMGuardProcessingView.swift
//  PAMFlow
//
//  Created by Dory on 03/07/2026.
//

import SwiftData
import SwiftUI

/// Renders PAMGuard import progress while its ViewModel owns detection processing.
struct PAMGuardProcessingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID
    let projectScanService: ProjectScanServicing
    let processingService: PAMGuardDetectionProcessingServicing

    @State private var viewModel: PAMGuardProcessingViewModel

    init(
        projectID: UUID,
        projectScanService: ProjectScanServicing,
        processingService: PAMGuardDetectionProcessingServicing
    ) {
        self.projectID = projectID
        self.projectScanService = projectScanService
        self.processingService = processingService
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
                        title: Strings.PAMGuardProcessing.title,
                        subtitle: Strings.PAMGuardProcessing.subtitle,
                        message: viewModel.message,
                        progress: viewModel.progress,
                        errorMessage: viewModel.errorMessage
                    ) {
                        if viewModel.errorMessage != nil {
                            if let project = viewModel.fetchProject(modelContext: modelContext) {
                                Button(Strings.PAMGuardProcessing.retry) {
                                    viewModel.start(project: project, modelContext: modelContext, appCoordinator: appCoordinator)
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
            viewModel.startIfNeeded(modelContext: modelContext, appCoordinator: appCoordinator)
        }
    }
}
