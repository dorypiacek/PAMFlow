//
//  ScanProjectView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftData
import SwiftUI

/// Renders scan progress for a project while `ScanProjectViewModel` owns scanning and cleanup.
struct ScanProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID

    @State private var viewModel: ScanProjectViewModel

    init(projectID: UUID) {
        self.projectID = projectID
        _viewModel = State(initialValue: ScanProjectViewModel(projectID: projectID))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    LoadingCardView(
                        title: Strings.ScanProject.title,
                        subtitle: Strings.ScanProject.subtitle,
                        message: viewModel.scanMessage,
                        progress: viewModel.progressFraction,
                        detail: viewModel.currentFileName,
                        errorMessage: viewModel.errorMessage
                    ) {
                        Button(Strings.ScanProject.backButton) {
                            viewModel.showsCancelWarning = true
                        }
                        .buttonStyle(.secondaryAction)
                    }
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task {
            await viewModel.scanProject(modelContext: modelContext, appCoordinator: appCoordinator)
        }
        .alert(
            Strings.ScanProject.cancelTitle,
            isPresented: $viewModel.showsCancelWarning,
        ) {
            Button(Strings.ScanProject.cancelConfirmButton, role: .destructive) {
                viewModel.removeProjectAndReturnToSetup(modelContext: modelContext, appCoordinator: appCoordinator)
            }

            Button(Strings.ScanProject.cancelDismissButton, role: .cancel) {}
        } message: {
            Text(Strings.ScanProject.cancelMessage)
        }
    }
}
