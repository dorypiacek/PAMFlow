//
//  ContentView.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import SwiftUI

/// Chooses the active screen from the app's current top-level route.
struct RootView: View {
    @Environment(AppCoordinator.self) private var appCoordinator

    var body: some View {
        VStack {
            routedContent
        }
        .buttonStyle(.secondaryAction)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }

    @ViewBuilder
    private var routedContent: some View {
        switch appCoordinator.route {
        case .welcome:
            WelcomeView()

        case .projectSelection:
            ProjectSelectionView()

        case .dataTypeSelection:
            DataTypeSelectionView()

        case .projectSetup(module: let module):
            ProjectSetupView(
                module: module,
                projectFileService: appCoordinator.dependencies.projectFileService,
                fileSelectionService: appCoordinator.dependencies.fileSelectionService
            )

        case .scanProject(projectID: let projectID):
            ScanProjectView(projectID: projectID)
            
        case .newProjectOverview(projectID: let projectID):
            NewProjectOverviewView(
                projectID: projectID,
                projectScanService: appCoordinator.dependencies.projectScanService
            )

        case .sharkTrackProcessing(projectID: let projectID):
            SharkTrackProcessingView(projectID: projectID)

        case .manualAudit(projectID: let projectID, startAtLastReviewed: let startAtLastReviewed):
            ManualAuditView(
                projectID: projectID,
                startAtLastReviewed: startAtLastReviewed,
                projectScanService: appCoordinator.dependencies.projectScanService,
                audioPreviewCacheService: appCoordinator.dependencies.audioPreviewCacheService
            )

        case .manualAuditOverview(projectID: let projectID):
            ManualAuditOverviewView(
                projectID: projectID,
                projectScanService: appCoordinator.dependencies.projectScanService
            )

        case .pamguardSetup(projectID: let projectID):
            PAMGuardSetupView(
                projectID: projectID,
                projectScanService: appCoordinator.dependencies.projectScanService,
                preparationService: appCoordinator.dependencies.pamGuardPreparationService
            )

        case .pamguardWaiting(projectID: let projectID):
            PAMGuardWaitingView(projectID: projectID)

        case .pamguardProcessing(projectID: let projectID):
            PAMGuardProcessingView(
                projectID: projectID,
                projectScanService: appCoordinator.dependencies.projectScanService,
                processingService: appCoordinator.dependencies.pamGuardDetectionProcessingService
            )

        case .projectCompletion(projectID: let projectID):
            ProjectCompletionView(
                projectID: projectID,
                projectScanService: appCoordinator.dependencies.projectScanService
            )
        }
    }
}
