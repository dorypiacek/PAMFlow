//
//  PAMGuardWaitingView.swift
//  PAMFlow
//
//  Created by Dory on 27/06/2026.
//

import SwiftData
import UI
import Core
import SwiftUI

/// Renders the waiting state while the user runs the generated PAMGuard template.
struct PAMGuardWaitingView: View {
    @Environment(\.modelContext) private var modelContext

    let projectID: UUID
    let workflowActions: WorkflowActionHandling

    @State private var viewModel: PAMGuardWaitingViewModel

    init(projectID: UUID, workflowActions: WorkflowActionHandling) {
        self.projectID = projectID
        self.workflowActions = workflowActions
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

                        Text(PAMStrings.Setup.waitingTitle)
                            .font(Fonts.screenTitle)
                            .multilineTextAlignment(.center)

                        Text(PAMStrings.Setup.waitingSubtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: Metrics.Layout.readableTextWidth, alignment: .center)
                        
                        if let project = viewModel.fetchProject(modelContext: modelContext) {
                            HStack(spacing: Spacing.medium) {
                                Button(PAMStrings.Setup.helpButton) {
                                    viewModel.showsPAMGuardHelp = true
                                }
                                .buttonStyle(.secondaryAction)

                                Button(PAMStrings.Setup.confirmRunFinished) {
                                    viewModel.confirmRunFinished(project: project, modelContext: modelContext, workflowActions: workflowActions)
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
