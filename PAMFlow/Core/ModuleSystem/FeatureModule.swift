//
//  FeatureModule.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Foundation

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

    func openLatestProject(_ project: Project)
    func openReadOnlyProject(_ project: Project)
}
