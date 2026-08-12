//
//  ProjectSetupModel.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation
import Observation

/// State and actions for creating a PAMFlow project for a selected data module.
@Observable
@MainActor
final class ProjectSetupModel {
    let module: WorkflowModule

    var selectedInputSource: ProjectInputSourceSelection?
    var selectedRecorderID: String?
    var projectName = ""
    var metadataOpcode = ""
    var metadataDate = ""
    var metadataDateRetrieved = ""
    var metadataLocation = ""
    var metadataDepth = ""
    var metadataBottomType = ""
    var metadataWaterTemperature = ""
    var createdProject: Project?
    var errorMessage: String?

    private let projectFileService: ProjectFileServicing
    private let fileSelectionService: FileSelecting

    init(
        module: WorkflowModule,
        projectFileService: ProjectFileServicing,
        fileSelectionService: FileSelecting
    ) {
        self.module = module
        self.projectFileService = projectFileService
        self.fileSelectionService = fileSelectionService
    }

    var canCreateProject: Bool {
        selectedInputSource != nil &&
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasRequiredMetadata
    }

    var hasRequiredMetadata: Bool {
        guard module.usesProjectMetadata else { return true }
        let hasCommonMetadata = !metadataOpcode.trimmed.isEmpty &&
            !metadataDate.trimmed.isEmpty &&
            !metadataLocation.trimmed.isEmpty &&
            !metadataDepth.trimmed.isEmpty
        guard module == .pamAudio else { return hasCommonMetadata }
        return hasCommonMetadata && !metadataDateRetrieved.trimmed.isEmpty
    }

    /// Guidance shown under raw data selection so users understand where the project will be saved.
    var inputSelectionGuidance: String {
        switch selectedInputSource {
        case .folder:
            return Strings.ProjectSetup.folderSelectionGuidance
        case .files:
            return Strings.ProjectSetup.fileSelectionGuidance
        case nil:
            return Strings.ProjectSetup.inputSelectionGuidance
        }
    }

    func selectInputSource(_ selection: ProjectInputSourceSelection) {
        AppLog.info("Project setup selected input source: \(selection.displayText)")
        selectedInputSource = selection
        if projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            projectName = projectFileService.suggestedProjectName(
                from: selection.displayURL ?? URL(fileURLWithPath: ""),
                module: module
            )
        }
        errorMessage = nil
        createdProject = nil
    }

    func selectInputSource() {
        guard let selection = fileSelectionService.selectInputSource(
            title: Strings.ProjectSetup.inputPanelTitle,
            message: Strings.ProjectSetup.inputPanelMessage
        ) else {
            return
        }

        selectInputSource(selection)
    }

    func createProject() -> Project? {
        AppLog.info("Project setup create requested")
        guard let selectedInputSource else {
            AppLog.info("Project setup create failed: missing input folder")
            errorMessage = Strings.ProjectSetup.missingInputFolder
            return nil
        }

        let trimmedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedProjectName.isEmpty else {
            AppLog.info("Project setup create failed: missing project name")
            errorMessage = Strings.ProjectSetup.missingProjectName
            return nil
        }

        do {
            AppLog.info("Creating project '\(trimmedProjectName)' for selected raw data")
            let project = try projectFileService.createProject(
                named: trimmedProjectName,
                inputSelection: selectedInputSource,
                moduleID: module.id
            )

            return finishCreatedProject(project)
        } catch {
            AppLog.info("Project setup initial create failed: \(error.localizedDescription)")
            return requestWritePermissionAndRetry(
                projectName: trimmedProjectName,
                inputSelection: selectedInputSource,
                moduleID: module.id,
                originalError: error
            )
        }
    }

    private func requestWritePermissionAndRetry(
        projectName: String,
        inputSelection: ProjectInputSourceSelection,
        moduleID: String,
        originalError: Error
    ) -> Project? {
        guard let containerURL = fileSelectionService.selectWritableProjectContainer(
            title: Strings.ProjectSetup.projectFolderPermissionTitle,
            message: Strings.ProjectSetup.projectFolderPermissionMessage,
            defaultURL: inputSelection.rawMediaFolderURL
        ) else {
            errorMessage = originalError.localizedDescription
            return nil
        }

        do {
            AppLog.info("Retrying project creation in user-approved folder \(containerURL.path)")
            let project = try projectFileService.createProject(
                named: projectName,
                inputSelection: inputSelection,
                moduleID: moduleID,
                projectContainerURL: containerURL
            )
            return finishCreatedProject(project)
        } catch {
            AppLog.info("Project setup retry create failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func finishCreatedProject(_ project: Project) -> Project {
        createdProject = project
        project.metadataOpcode = metadataOpcode.trimmed.nilIfEmpty
        project.metadataDate = metadataDate.trimmed.nilIfEmpty
        project.metadataDateRetrieved = metadataDateRetrieved.trimmed.nilIfEmpty
        project.metadataLocation = metadataLocation.trimmed.nilIfEmpty
        project.metadataDepth = metadataDepth.trimmed.nilIfEmpty
        project.metadataBottomType = metadataBottomType.trimmed.nilIfEmpty
        project.metadataWaterTemperature = metadataWaterTemperature.trimmed.nilIfEmpty
        AppLog.info("Created project '\(project.name)' at \(project.rootFolderURL?.path ?? "unknown")")
        return project
    }
}
