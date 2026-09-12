//
//  FeatureModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Foundation
import SwiftUI

/// A selectable workflow capability included in a particular build.
@MainActor
protocol FeatureModule {
    var details: ModuleDetails { get }

    func makeCoordinator(context: ModuleContext) -> ModuleCoordinating
}

/// App services exposed to feature modules through a single context object.
@MainActor
struct ModuleContext {
    let dependencies: Dependencies
    let appCoordinator: AppCoordinating

    init(dependencies: Dependencies, appCoordinator: AppCoordinating) {
        self.dependencies = dependencies
        self.appCoordinator = appCoordinator
    }
}

/// Coordinator owned by a feature module.
@MainActor
protocol ModuleCoordinating: AnyObject {
    var moduleID: ModuleID { get }

    func startProject() -> AnyView
    func makeScreen(for route: ModuleScreenRoute) -> AnyView
    func previousRoute(for route: ModuleScreenRoute) -> AppRoute
    func openNextStep(for project: Project, from route: AppRoute, startAtLastReviewed: Bool)
    func openLatestProject(_ project: Project, startAtLastReviewed: Bool)
    func openReadOnlyProject(_ project: Project)
}

extension ModuleCoordinating {
    func openNextStep(for project: Project, from route: AppRoute, startAtLastReviewed: Bool = false) {
        openLatestProject(project, startAtLastReviewed: startAtLastReviewed)
    }

    func openLatestProject(_ project: Project) {
        openLatestProject(project, startAtLastReviewed: false)
    }
}
