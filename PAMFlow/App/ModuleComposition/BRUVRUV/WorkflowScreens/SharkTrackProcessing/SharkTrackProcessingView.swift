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
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID

    @State private var viewModel: SharkTrackProcessingViewModel

    init(projectID: UUID) {
        self.projectID = projectID
        _viewModel = State(initialValue: SharkTrackProcessingViewModel(projectID: projectID))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    LoadingCardView(
                        title: Strings.SharkTrackProcessing.title,
                        subtitle: Strings.SharkTrackProcessing.subtitle,
                        message: viewModel.statusMessage,
                        progress: viewModel.progress,
                        detail: viewModel.detailMessage,
                        errorMessage: viewModel.errorMessage
                    ) {
                        if viewModel.errorMessage != nil {
                            Button(Strings.SharkTrackProcessing.retryButton) {
                                Task {
                                    await viewModel.processProject(modelContext: modelContext, appCoordinator: appCoordinator)
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
            await viewModel.processProject(modelContext: modelContext, appCoordinator: appCoordinator)
        }
        .task(id: viewModel.isProcessing) {
            guard viewModel.isProcessing else { return }
            await viewModel.runProgressHeartbeat()
        }
    }
}
