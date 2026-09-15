//
//  Dependencies.swift
//  PAMFlow
//
//  Created by Dory on 07/06/2026.
//

import Foundation
import Core
import UI

/// Shared app services injected into app screens and feature modules.
@MainActor
struct Dependencies: SharedAppDependencies {
    let projectFileService: ProjectFileServicing
    let projectScanService: ProjectScanServicing
    let fileSelectionService: FileSelecting
}
