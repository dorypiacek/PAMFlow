//
//  ModuleDetails.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Display and file-selection details for a feature module included in the app.
public struct ModuleDetails: Hashable, Sendable {
    public let id: ModuleID
    public let name: String
    public let subtitle: String
    public let iconName: String
    public let projectNamePrefix: String
    public let libraryFolderName: String
    public let supportedFileExtensions: Set<String>
    public let generatedArtifactFolderNames: Set<String>

    public init(
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
