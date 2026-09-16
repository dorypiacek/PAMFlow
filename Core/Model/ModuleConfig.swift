//
//  ModuleConfig.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

/// Module-owned file and folder names used by shared project services.
public struct ModuleFileConfiguration: Hashable, Sendable {
    public let sourceDirectoryName: String
    public let workDirectoryName: String
    public let scanSummaryFileName: String
    public let generatedArtifactFolderNames: Set<String>

    public init(
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
public struct ModuleConfiguration {
    public let details: ModuleDetails
    public let fileConfiguration: ModuleFileConfiguration
    public let setupConfiguration: @MainActor () -> ProjectSetupConfiguration

    public init(
        details: ModuleDetails,
        fileConfiguration: ModuleFileConfiguration,
        setupConfiguration: @escaping @MainActor () -> ProjectSetupConfiguration
    ) {
        self.details = details
        self.fileConfiguration = fileConfiguration
        self.setupConfiguration = setupConfiguration
    }
}
