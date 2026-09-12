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
    static func makeCatalog(context: ModuleContext) -> ModuleCatalog {
        ModuleCatalog()
    }
}
