//
//  PAMGuardSetupView.swift
//  PAMFlow
//
//  Created by Dory on 17/06/2026.
//

import SwiftData
import SwiftUI

/// Renders PAMGuard setup controls while its ViewModel prepares the external project package.
struct PAMGuardSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID
    let projectScanService: ProjectScanServicing
    let preparationService: PAMGuardPreparationServicing

    @State private var viewModel: PAMGuardSetupViewModel

    init(
        projectID: UUID,
        projectScanService: ProjectScanServicing,
        preparationService: PAMGuardPreparationServicing
    ) {
        self.projectID = projectID
        self.projectScanService = projectScanService
        self.preparationService = preparationService
        _viewModel = State(
            initialValue: PAMGuardSetupViewModel(
                projectID: projectID,
                projectScanService: projectScanService,
                preparationService: preparationService
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.large) {
                        Text(Strings.PAMGuardSetup.title)
                            .font(Fonts.screenTitle)

                        Text(Strings.PAMGuardSetup.subtitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: Metrics.Layout.readableTextWidth, alignment: .leading)

                        if let project = viewModel.fetchProject(modelContext: modelContext) {
                            setupContent(project: project)
                        } else {
                            Text(Strings.Common.projectNotFound)
                                .foregroundStyle(AppColors.error)
                        }
                    }
                    .padding(Spacing.xxLarge)
                    .frame(maxWidth: Metrics.Layout.loadingCardWidth, alignment: .leading)
                    .glassySurface()
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .sheet(isPresented: $viewModel.showsPAMGuardHelp) {
            PAMGuardRunHelpView(
                onShowPamguardFolder: viewModel.pamguardFolderRevealAction(modelContext: modelContext)
            ) {
                viewModel.showsPAMGuardHelp = false
            }
        }
        .task {
            viewModel.restorePreparedResultIfNeeded(modelContext: modelContext)
        }
    }

    private func setupContent(project: Project) -> some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Picker(Strings.PAMGuardSetup.question, selection: $viewModel.selectedTarget) {
                Text(Strings.PAMGuardSetup.selectDetectionTarget).tag(PAMGuardPreparationService.DetectionTarget?.none)
                ForEach(PAMGuardPreparationService.DetectionTarget.allCases) { target in
                    Text(target.title).tag(Optional(target))
                }
            }
            .frame(width: Metrics.Layout.pickerWidth, alignment: .leading)
            .onChange(of: viewModel.selectedTarget) { _, target in
                guard target != nil else { return }
                viewModel.prepare(project: project, modelContext: modelContext)
            }

            if viewModel.isPreparing {
                HStack(spacing: Spacing.small) {
                    ProgressView()
                    Text(Strings.PAMGuardSetup.preparing)
                        .foregroundStyle(.secondary)
                }
            }

            if let result = viewModel.result {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text(Strings.PAMGuardSetup.prepared)
                        .font(Fonts.subtitle)

                    Text(String(format: Strings.PAMGuardSetup.selectedInputCountFormat, result.linkedInputCount))
                        .foregroundStyle(.secondary)

                    Text(Strings.PAMGuardSetup.instructions)
                        .foregroundStyle(.secondary)

                    HStack(spacing: Spacing.medium) {
                        Button(Strings.PAMGuardSetup.showInFinder) {
                            viewModel.revealTemplateInFinder(result.templateURL, project: project)
                        }
                        .buttonStyle(.secondaryAction)

                        Button(Strings.PAMGuardSetup.helpButton) {
                            viewModel.showsPAMGuardHelp = true
                        }
                        .buttonStyle(.secondaryAction)
                    }
                }
                .padding(Spacing.medium)
                .glassySurface()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppColors.error)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: Spacing.medium) {
                Button(Strings.PAMGuardSetup.backButton) {
                    appCoordinator.goToPreviousStep(for: project)
                }
                .buttonStyle(.secondaryAction)

                Button(Strings.PAMGuardSetup.continueButton) {
                    viewModel.continueWorkflow(project: project, modelContext: modelContext, appCoordinator: appCoordinator)
                }
                .buttonStyle(.primaryAction)
                .disabled(viewModel.result == nil)
            }
        }
    }
}
