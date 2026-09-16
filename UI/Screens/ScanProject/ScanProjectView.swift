//
//  ScanProjectView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftData
import Core
import SwiftUI

/// Renders scan progress for a project while the injected ViewModel owns scanning and cleanup.
public struct ScanProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCoordinator) private var appCoordinator

    private var coordinator: any AppCoordinating {
        guard let appCoordinator else {
            fatalError("App coordinator must be injected before rendering shared UI")
        }
        return appCoordinator
    }

    public let projectID: UUID

    @State private var viewModel: ScanProjectViewModel

    /// Creates a scan screen for a project using module-provided scan behavior.
    public init(
        projectID: UUID,
        supportedFileExtensions: Set<String>,
        scanAnalyzer: ProjectScanAnalyzing
    ) {
        self.projectID = projectID
        _viewModel = State(initialValue: ScanProjectViewModel(
            projectID: projectID,
            supportedFileExtensions: supportedFileExtensions,
            scanAnalyzer: scanAnalyzer
        ))
    }

    public var body: some View {
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
            await viewModel.scanProject(modelContext: modelContext, coordinator: coordinator)
        }
        .alert(
            Strings.ScanProject.cancelTitle,
            isPresented: $viewModel.showsCancelWarning,
        ) {
            Button(Strings.ScanProject.cancelConfirmButton, role: .destructive) {
                viewModel.removeProjectAndReturnToSetup(modelContext: modelContext, coordinator: coordinator)
            }

            Button(Strings.ScanProject.cancelDismissButton, role: .cancel) {}
        } message: {
            Text(Strings.ScanProject.cancelMessage)
        }
    }
}
