//
//  ProjectSetupViewModel.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

/// State and actions for creating a PAMFlow project for a selected data module.
@MainActor
protocol ProjectSetupViewModelType: AnyObject {
    var configuration: ProjectSetupConfiguration { get }
    var selectedInputSource: ProjectInputSourceSelection? { get }
    var projectName: String { get set }
    var metadataValues: ProjectMetadataValues { get set }
    var metadataFileName: String? { get }
    var selectedMetadataRowID: String { get set }
    var metadataSelectionOptions: [String] { get }
    var createdProject: Project? { get }
    var errorMessage: String? { get set }
    var canCreateProject: Bool { get }
    var inputSelectionGuidance: String { get }
    var metadataSelectionTitle: String { get }
    var showsMetadataSelection: Bool { get }

    func metadataValue(for fieldID: String) -> String
    func setMetadataValue(_ value: String, for fieldID: String)
    func selectInputSource()
    func loadCachedMetadataTable()
    func uploadMetadataTable()
    func applySelectedMetadataRow()
    func createProject() -> Project?
}

@Observable
@MainActor
class BaseProjectSetupViewModel: ProjectSetupViewModelType {
    let configuration: ProjectSetupConfiguration

    var selectedInputSource: ProjectInputSourceSelection?
    var selectedRecorderID: String?
    var projectName = ""
    var metadataValues = ProjectMetadataValues()
    var metadataFileName: String?
    var selectedMetadataRowID = ""
    var metadataSelectionOptions: [String] = []
    var createdProject: Project?
    var errorMessage: String?

    private var metadataTable: ProjectMetadataTable?
    private let projectFileService: ProjectFileServicing
    private let fileSelectionService: FileSelecting

    init(
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
            message: Strings.ProjectSetup.inputPanelMessage
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
    let fileName: String
    let rows: [ProjectMetadataRow]

    init(url: URL, fields: [ProjectMetadataField]) throws {
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
    let valuesByFieldID: [String: String]

    func value(for fieldID: String) -> String {
        valuesByFieldID[fieldID] ?? ""
    }

    func identifierValue(for fieldID: String) -> String? {
        value(for: fieldID).nilIfEmpty
    }
}

private struct ProjectMetadataColumnMapping {
    let indexesByFieldID: [String: Int]

    init(header: [String], fields: [ProjectMetadataField]) {
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
