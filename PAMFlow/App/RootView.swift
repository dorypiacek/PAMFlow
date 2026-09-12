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

        case .moduleFlow(moduleID: let moduleID):
            if let module = appCoordinator.moduleCatalog.module(for: moduleID) {
                module.makeCoordinator(
                    context: ModuleContext(dependencies: appCoordinator.dependencies, appCoordinator: appCoordinator)
                )
                .startProject()
            } else {
                ProjectSelectionView()
            }

        case .moduleScreen(let screen):
            if let module = appCoordinator.moduleCatalog.module(for: screen.moduleID) {
                module.makeCoordinator(
                    context: ModuleContext(dependencies: appCoordinator.dependencies, appCoordinator: appCoordinator)
                )
                .makeScreen(for: screen)
            } else {
                ProjectSelectionView()
            }
        }
    }
}
