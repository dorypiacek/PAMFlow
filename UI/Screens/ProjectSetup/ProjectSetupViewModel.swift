//
//  ProjectSetupViewModel.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation
import Core
import Observation
import AppKit
import SwiftData
import UniformTypeIdentifiers

/// Defines state and actions for creating a project for a selected data module.
@MainActor
protocol ProjectSetupViewModelType: AnyObject {
    /// Module-specific setup rules, metadata fields, and project naming.
    var configuration: ProjectSetupConfiguration { get }
    /// Selected raw input folder or file set.
    var selectedInputSource: ProjectInputSourceSelection? { get }
    /// User-entered project display name.
    var projectName: String { get set }
    /// Current metadata values keyed by module-defined field identifiers.
    var metadataValues: ProjectMetadataValues { get set }
    /// Name of the uploaded metadata CSV, when one is loaded.
    var metadataFileName: String? { get }
    /// Identifier of the selected metadata row.
    var selectedMetadataRowID: String { get set }
    /// Row identifiers available from the uploaded metadata table.
    var metadataSelectionOptions: [String] { get }
    /// Most recently created project, used for success feedback.
    var createdProject: Project? { get }
    /// User-facing setup or persistence error.
    var errorMessage: String? { get set }
    /// Indicates whether all required inputs are present and valid.
    var canCreateProject: Bool { get }
    /// Guidance text describing the current input-source selection.
    var inputSelectionGuidance: String { get }
    /// Title for the metadata row picker.
    var metadataSelectionTitle: String { get }
    /// Indicates whether an uploaded metadata table can be selected from.
    var showsMetadataSelection: Bool { get }

    /// Returns a metadata value for display or editing.
    func metadataValue(for fieldID: String) -> String
    /// Updates one metadata value.
    func setMetadataValue(_ value: String, for fieldID: String)
    /// Opens the input-source picker and stores the selected source.
    func selectInputSource()
    /// Restores the last uploaded metadata table when security-scoped access is still available.
    func loadCachedMetadataTable()
    /// Prompts for a metadata CSV and loads selectable rows from it.
    func uploadMetadataTable()
    /// Copies values from the selected metadata row into current setup metadata.
    func applySelectedMetadataRow()
    /// Creates the project folder structure and returns an unsaved project model.
    func createProject() -> Project?
    /// Creates and persists a project in SwiftData.
    func createAndSaveProject(modelContext: ModelContext) -> Project?
}

/// Base ViewModel for module-configurable project setup.
@Observable
@MainActor
public class BaseProjectSetupViewModel: ProjectSetupViewModelType {
    /// Module-specific setup rules, metadata fields, and project naming.
    public let configuration: ProjectSetupConfiguration

    /// Selected raw input folder or file set.
    var selectedInputSource: ProjectInputSourceSelection?
    /// Selected recorder identifier retained for compatibility with existing metadata flows.
    var selectedRecorderID: String?
    /// User-entered project display name.
    var projectName = ""
    /// Current metadata values keyed by module-defined field identifiers.
    var metadataValues = ProjectMetadataValues()
    /// Name of the uploaded metadata CSV, when one is loaded.
    var metadataFileName: String?
    /// Identifier of the selected metadata row.
    var selectedMetadataRowID = ""
    /// Row identifiers available from the uploaded metadata table.
    var metadataSelectionOptions: [String] = []
    /// Most recently created project, used for success feedback.
    var createdProject: Project?
    /// User-facing setup or persistence error.
    var errorMessage: String?

    /// Parsed metadata table loaded from the most recent CSV upload.
    private var metadataTable: ProjectMetadataTable?
    /// Service that creates project folders and suggests names.
    private let projectFileService: ProjectFileServicing
    /// Service that presents input and destination selection UI.
    private let fileSelectionService: FileSelecting

    public init(
        configuration: ProjectSetupConfiguration,
        projectFileService: ProjectFileServicing,
        fileSelectionService: FileSelecting
    ) {
        self.configuration = configuration
        self.projectFileService = projectFileService
        self.fileSelectionService = fileSelectionService
    }

    var canCreateProject: Bool {
        selectedInputSource != nil &&
        !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasRequiredMetadata
    }

    var hasRequiredMetadata: Bool {
        guard configuration.usesProjectMetadata else { return true }
        return configuration.isMetadataComplete(metadataValues)
    }

    func metadataValue(for fieldID: String) -> String {
        metadataValues.value(for: fieldID)
    }

    func setMetadataValue(_ value: String, for fieldID: String) {
        metadataValues.setValue(value, for: fieldID)
    }

    var metadataSelectionTitle: String {
        metadataSelectionField?.title ?? Strings.ProjectSetup.opcode
    }

    var showsMetadataSelection: Bool {
        metadataTable != nil && metadataSelectionField != nil
    }

    var metadataSelectionField: ProjectMetadataField? {
        guard let fieldID = configuration.metadataSelectionFieldID else { return nil }
        return configuration.requiredMetadataFields.first { $0.id == fieldID }
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
                projectNamePrefix: configuration.module.projectNamePrefix
            )
        }
        errorMessage = nil
        createdProject = nil
    }

    func selectInputSource() {
        guard let selection = fileSelectionService.selectInputSource(
            title: Strings.ProjectSetup.inputPanelTitle,
            message: Strings.ProjectSetup.inputPanelMessage,
            allowedFileExtensions: configuration.selectableFileExtensions
        ) else {
            return
        }

        selectInputSource(selection)
    }

    func loadCachedMetadataTable() {
        guard configuration.usesProjectMetadata,
              let bookmark = UserDefaults.standard.data(forKey: configuration.metadataCacheKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        try? loadMetadataTable(from: url)
    }

    func uploadMetadataTable() {
        let panel = NSOpenPanel()
        panel.title = String(format: Strings.ProjectSetup.uploadMetadataCSVTitleFormat, configuration.module.name)
        panel.message = configuration.metadataUploadMessage
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: configuration.metadataCacheKey)
            try loadMetadataTable(from: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applySelectedMetadataRow() {
        guard let selectionFieldID = configuration.metadataSelectionFieldID,
              let row = metadataTable?.rows.first(where: { $0.identifierValue(for: selectionFieldID) == selectedMetadataRowID }) else { return }
        for field in configuration.requiredMetadataFields {
            setMetadataValue(row.value(for: field.id), for: field.id)
        }
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
                moduleID: configuration.module.id.rawValue
            )

            return finishCreatedProject(project)
        } catch {
            AppLog.info("Project setup initial create failed: \(error.localizedDescription)")
            return requestWritePermissionAndRetry(
                projectName: trimmedProjectName,
                inputSelection: selectedInputSource,
                moduleID: configuration.module.id.rawValue,
                originalError: error
            )
        }
    }

    func createAndSaveProject(modelContext: ModelContext) -> Project? {
        guard let project = createProject() else { return nil }

        modelContext.insert(project)
        do {
            try modelContext.save()
            return project
        } catch {
            errorMessage = error.localizedDescription
            return nil
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
        configuration.applyMetadata(metadataValues, project)
        AppLog.info("Created project '\(project.name)' at \(project.rootFolderURL?.path ?? "unknown")")
        return project
    }

    private func loadMetadataTable(from url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let table = try ProjectMetadataTable(url: url, fields: configuration.requiredMetadataFields)
        metadataTable = table
        metadataFileName = table.fileName
        selectedMetadataRowID = ""
        metadataSelectionOptions = selectionOptions(from: table)
        errorMessage = nil
    }

    private func selectionOptions(from table: ProjectMetadataTable) -> [String] {
        guard let selectionFieldID = configuration.metadataSelectionFieldID else { return [] }
        return table.rows.compactMap { $0.identifierValue(for: selectionFieldID) }
    }
}

private struct ProjectMetadataTable {
    public let fileName: String
    public let rows: [ProjectMetadataRow]

    public init(url: URL, fields: [ProjectMetadataField]) throws {
        fileName = url.lastPathComponent
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsedRows = Self.parseCSV(text)
        guard let header = parsedRows.first else {
            rows = []
            return
        }

        let mapping = ProjectMetadataColumnMapping(header: header, fields: fields)
        rows = parsedRows.dropFirst().compactMap { values in
            ProjectMetadataRow(valuesByFieldID: mapping.values(in: values))
        }
        .filter { !$0.valuesByFieldID.values.allSatisfy(\.isEmpty) }
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        text
            .split(whereSeparator: \.isNewline)
            .map { parseCSVLine(String($0)) }
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                isQuoted.toggle()
            } else if character == "," && !isQuoted {
                values.append(current.trimmed)
                current = ""
            } else {
                current.append(character)
            }
        }

        values.append(current.trimmed)
        return values
    }
}

private struct ProjectMetadataRow {
    public let valuesByFieldID: [String: String]

    func value(for fieldID: String) -> String {
        valuesByFieldID[fieldID] ?? ""
    }

    func identifierValue(for fieldID: String) -> String? {
        value(for: fieldID).nilIfEmpty
    }
}

private struct ProjectMetadataColumnMapping {
    public let indexesByFieldID: [String: Int]

    public init(header: [String], fields: [ProjectMetadataField]) {
        indexesByFieldID = fields.reduce(into: [:]) { indexes, field in
            let candidates = ([field.title] + field.csvAliases).map(\.normalizedFieldName)
            indexes[field.id] = Self.index(in: header, matching: candidates)
        }
    }

    func values(in values: [String]) -> [String: String] {
        indexesByFieldID.reduce(into: [:]) { result, fieldIndex in
            guard values.indices.contains(fieldIndex.value) else { return }
            result[fieldIndex.key] = values[fieldIndex.value].trimmed
        }
    }

    private static func index(in header: [String], matching candidates: [String]) -> Int? {
        header.firstIndex { rawName in
            let normalized = rawName.normalizedFieldName
            return candidates.contains { normalized.contains($0.normalizedFieldName) }
        }
    }
}
