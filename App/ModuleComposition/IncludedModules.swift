//
//  IncludedModules.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//
import Core
import Foundation
import UI

#if !PAMFLOW_CUSTOM_MODULE_SELECTION || PAMFLOW_INCLUDE_BRUV
import BRUV
#endif

#if !PAMFLOW_CUSTOM_MODULE_SELECTION || PAMFLOW_INCLUDE_PAM
import PAM
#endif

/// Build-composition entry point for feature modules included in this app.
@MainActor
enum IncludedModules {
    /// Builds the catalog of feature modules compiled into this app target.
    static func makeCatalog(provider: IncludedModuleProviding? = nil) -> ModuleCatalog {
        ModuleCatalog(modules: (provider ?? StaticIncludedModuleProvider()).modules)
    }
}

/// Supplies feature modules for an app build configuration.
@MainActor
protocol IncludedModuleProviding {
    /// Workflow modules available in this build.
    var modules: [FeatureModule] { get }
}

/// Static build-time module provider used by the app target.
@MainActor
struct StaticIncludedModuleProvider: IncludedModuleProviding {
    private let includedProjectTypes: [IncludedProjectType]

    /// Creates a provider for the selected project types.
    init(includedProjectTypes: [IncludedProjectType] = IncludedProjectType.allCases) {
        self.includedProjectTypes = includedProjectTypes
    }

    /// Feature modules mapped from the selected project types.
    var modules: [FeatureModule] {
        includedProjectTypes.map(makeModule)
    }

    private func makeModule(for projectType: IncludedProjectType) -> FeatureModule {
        switch projectType {
        #if !PAMFLOW_CUSTOM_MODULE_SELECTION || PAMFLOW_INCLUDE_PAM
        case .pam:
            PAMWorkflowModule()
        #endif
        #if !PAMFLOW_CUSTOM_MODULE_SELECTION || PAMFLOW_INCLUDE_BRUV
        case .bruv:
            BRUVWorkflowModule(projectType: .bruv)
        case .ruv:
            BRUVWorkflowModule(projectType: .ruv)
        #endif
        }
    }

}

/// Project types compiled into the app target.
enum IncludedProjectType: CaseIterable {
    #if !PAMFLOW_CUSTOM_MODULE_SELECTION || PAMFLOW_INCLUDE_PAM
    case pam
    #endif
    #if !PAMFLOW_CUSTOM_MODULE_SELECTION || PAMFLOW_INCLUDE_BRUV
    case bruv
    case ruv
    #endif
}
