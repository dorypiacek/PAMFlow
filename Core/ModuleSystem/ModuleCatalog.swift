//
//  ModuleCatalog.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Catalog of feature modules included in the current app build.
@MainActor
final class ModuleCatalog {
    private var modulesByID: [ModuleID: FeatureModule] = [:]

    var modules: [FeatureModule] {
        modulesByID.values.sorted { lhs, rhs in
            lhs.details.name.localizedStandardCompare(rhs.details.name) == .orderedAscending
        }
    }

    var details: [ModuleDetails] {
        modules.map(\.details)
    }

    init(modules: [FeatureModule] = []) {
        modules.forEach(register)
    }

    func register(_ module: FeatureModule) {
        modulesByID[module.details.id] = module
    }

    func module(for id: ModuleID) -> FeatureModule? {
        modulesByID[id]
    }
}
