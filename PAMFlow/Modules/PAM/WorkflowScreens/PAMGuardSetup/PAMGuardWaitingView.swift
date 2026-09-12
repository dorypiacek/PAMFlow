//
//  PAMGuardWaitingView.swift
//  PAMFlow
//
//  Created by Dory on 27/06/2026.
//

import SwiftData
import SwiftUI

/// Renders the waiting state while the user runs the generated PAMGuard template.
struct PAMGuardWaitingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID

    @State private var viewModel: PAMGuardWaitingViewModel

    init(projectID: UUID) {
        self.projectID = projectID
        _viewModel = State(initialValue: PAMGuardWaitingViewModel(projectID: projectID))
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .center, spacing: Spacing.large) {
                        ProgressView()
                            .controlSize(.large)

                        Text(Strings.PAMGuardSetup.waitingTitle)
                            .font(Fonts.screenTitle)
                            .multilineTextAlignment(.center)

                        Text(Strings.PAMGuardSetup.waitingSubtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: Metrics.Layout.readableTextWidth, alignment: .center)
                        
                        if let project = viewModel.fetchProject(modelContext: modelContext) {
                            HStack(spacing: Spacing.medium) {
                                Button(Strings.PAMGuardSetup.helpButton) {
                                    viewModel.showsPAMGuardHelp = true
                                }
                                .buttonStyle(.secondaryAction)

                                Button(Strings.PAMGuardSetup.confirmRunFinished) {
                                    viewModel.confirmRunFinished(project: project, modelContext: modelContext, appCoordinator: appCoordinator)
                                }
                                .buttonStyle(.primaryAction)
                            }
                        }
                    }
                    .padding(Spacing.xxLarge)
                    .frame(maxWidth: Metrics.Layout.loadingCardWidth, alignment: .center)
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
    }
}
