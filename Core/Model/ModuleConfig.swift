//
//  ModuleConfig.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

/// Module-owned file and folder names used by shared project services.
struct ModuleFileConfiguration: Hashable, Sendable {
    let sourceDirectoryName: String
    let workDirectoryName: String
    let scanSummaryFileName: String
    let generatedArtifactFolderNames: Set<String>

    init(
        sourceDirectoryName: String = ProjectFileNames.sourceDirectory,
        workDirectoryName: String = ProjectFileNames.workDirectory,
        scanSummaryFileName: String = ProjectFileNames.scanSummary,
        generatedArtifactFolderNames: Set<String> = []
    ) {
        self.sourceDirectoryName = sourceDirectoryName
        self.workDirectoryName = workDirectoryName
        self.scanSummaryFileName = scanSummaryFileName
        self.generatedArtifactFolderNames = generatedArtifactFolderNames
    }
}

/// Module-owned workflow configuration consumed by shared UI and services.
struct ModuleConfiguration {
    let details: ModuleDetails
    let fileConfiguration: ModuleFileConfiguration
    let setupConfiguration: @MainActor () -> ProjectSetupConfiguration

    init(
        details: ModuleDetails,
        fileConfiguration: ModuleFileConfiguration,
        setupConfiguration: @escaping @MainActor () -> ProjectSetupConfiguration
    ) {
        self.details = details
        self.fileConfiguration = fileConfiguration
        self.setupConfiguration = setupConfiguration
    }
}
