//
//  ModuleDetails.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Display and file-selection details for a feature module included in the app.
struct ModuleDetails: Hashable, Sendable {
    let id: ModuleID
    let name: String
    let subtitle: String
    let iconName: String
    let projectNamePrefix: String
    let libraryFolderName: String
    let supportedFileExtensions: Set<String>
    let generatedArtifactFolderNames: Set<String>

    init(
        id: ModuleID,
        name: String,
        subtitle: String,
        iconName: String,
        projectNamePrefix: String,
        libraryFolderName: String,
        supportedFileExtensions: Set<String>,
        generatedArtifactFolderNames: Set<String> = []
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.iconName = iconName
        self.projectNamePrefix = projectNamePrefix
        self.libraryFolderName = libraryFolderName
        self.supportedFileExtensions = supportedFileExtensions
        self.generatedArtifactFolderNames = generatedArtifactFolderNames
    }
}
