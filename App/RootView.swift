//
//  ContentView.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import SwiftUI
import UI
import Core

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

        case .moduleWorkflow:
            let _ = appCoordinator.workflowRevision
            if let coordinator = appCoordinator.activeModuleCoordinator {
                coordinator.currentScreen
            } else {
                ProjectSelectionView()
            }
        }
    }
}
