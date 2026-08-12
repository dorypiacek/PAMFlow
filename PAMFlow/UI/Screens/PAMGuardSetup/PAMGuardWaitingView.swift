//
//  PAMGuardWaitingView.swift
//  PAMFlow
//
//  Created by Dory on 27/06/2026.
//

import SwiftData
import SwiftUI

/// Holding screen shown while the user runs the generated PAMGuard template.
struct PAMGuardWaitingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID

    @State private var showsPAMGuardHelp = false

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
                        
                        if let project = fetchProject() {
                            HStack(spacing: Spacing.medium) {
                                Button(Strings.PAMGuardSetup.helpButton) {
                                    showsPAMGuardHelp = true
                                }
                                .buttonStyle(.secondaryAction)

                                Button(Strings.PAMGuardSetup.confirmRunFinished) {
                                    project.workflowStatus = .processingRunImported
                                    project.lastOpenedAt = .now
                                    try? modelContext.save()
                                    appCoordinator.openPAMGuardProcessing(project)
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
        .sheet(isPresented: $showsPAMGuardHelp) {
            PAMGuardRunHelpView(
                onShowPamguardFolder: pamguardFolderRevealAction()
            ) {
                showsPAMGuardHelp = false
            }
        }
    }

    private func pamguardFolderRevealAction() -> (() -> Void)? {
        guard let project = fetchProject(),
              let projectRootURL = project.rootFolderURL else {
            return nil
        }

        return {
            let accessed = projectRootURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    projectRootURL.stopAccessingSecurityScopedResource()
                }
            }

            FileSelectionService.revealInFinder(projectRootURL.appendingPathComponent(ProjectFileNames.pamguardDirectory))
        }
    }

    private func fetchProject() -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
