//
//  IncludedModules.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Foundation

/// Build-composition entry point for feature modules included in this app.
@MainActor
enum IncludedModules {
    static func makeCatalog(provider: IncludedModuleProviding? = nil) -> ModuleCatalog {
        ModuleCatalog(modules: (provider ?? StaticIncludedModuleProvider()).modules)
    }
}

@MainActor
protocol IncludedModuleProviding {
    var modules: [FeatureModule] { get }
}

@MainActor
struct StaticIncludedModuleProvider: IncludedModuleProviding {
    private let includedProjectTypes: [IncludedProjectType]

    init(includedProjectTypes: [IncludedProjectType] = IncludedProjectType.allCases) {
        self.includedProjectTypes = includedProjectTypes
    }

    var modules: [FeatureModule] {
        includedProjectTypes.map(makeModule)
    }

    private func makeModule(for projectType: IncludedProjectType) -> FeatureModule {
        switch projectType {
        case .pam:
            PAMWorkflowModule()
        case .bruv:
            BRUVWorkflowModule(projectType: .bruv)
        case .ruv:
            BRUVWorkflowModule(projectType: .ruv)
        }
    }
}

enum IncludedProjectType: CaseIterable {
    case pam
    case bruv
    case ruv
}
