//
//  ModuleCatalog.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import Core

/// Catalog of feature modules included in the current app build.
@MainActor
public final class ModuleCatalog {
    private var modulesByID: [ModuleID: FeatureModule] = [:]

    public var modules: [FeatureModule] {
        modulesByID.values.sorted { lhs, rhs in
            lhs.details.name.localizedStandardCompare(rhs.details.name) == .orderedAscending
        }
    }

    public var details: [ModuleDetails] {
        modules.map(\.details)
    }

    public init(modules: [FeatureModule] = []) {
        modules.forEach(register)
    }

    public func register(_ module: FeatureModule) {
        modulesByID[module.details.id] = module
    }

    public func module(for id: ModuleID) -> FeatureModule? {
        modulesByID[id]
    }
}
