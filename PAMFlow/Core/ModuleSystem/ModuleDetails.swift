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
    let title: String
    let subtitle: String
    let iconName: String
    let projectNamePrefix: String
    let libraryFolderName: String
    let supportedFileExtensions: Set<String>

    init(
        id: ModuleID,
        title: String,
        subtitle: String,
        iconName: String,
        projectNamePrefix: String,
        libraryFolderName: String,
        supportedFileExtensions: Set<String>
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.projectNamePrefix = projectNamePrefix
        self.libraryFolderName = libraryFolderName
        self.supportedFileExtensions = supportedFileExtensions
    }
}
