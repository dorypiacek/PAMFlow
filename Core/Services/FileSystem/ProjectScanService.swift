//
//  ProjectScanService.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation

/// Scan operations and summary loading used across processing and overview screens.
@MainActor
protocol ProjectScanServicing {
    /// Discovers source files that match a module-provided extension list.
    func scanInventory(
        project: Project,
        supportedFileExtensions: Set<String>,
        onProgress: @escaping @Sendable (ProjectScanService.Progress) -> Void
    ) async throws -> ProjectScanInventory

    /// Creates and writes the persisted scan summary after module-specific analysis.
    func makeSummary(
        inventory: ProjectScanInventory,
        analyzedFiles: [ProjectScanFile],
        warnings: [String],
        attributes: [String: ScanAttributeValue]
    ) throws -> ProjectScanSummary

    /// Loads the scan summary that was previously written into the project work folder.
    func loadSummary(for project: Project) throws -> ProjectScanSummary
}

/// Discovers project input files and loads persisted scan summaries.
///
/// Core owns only the module-agnostic parts of scanning: resolving project
/// folders, enumerating files, emitting progress, and serializing the shared
/// summary format. Feature modules decide which file types to include and how to
/// analyze each file before asking Core to write the final summary.
final class ProjectScanService: ProjectScanServicing {
    init() {}

    /// User-visible scan progress emitted by the scanner process.
    struct Progress: Sendable {
        let currentFileIndex: Int?
        let totalFileCount: Int?
        let currentFile: String?
        let message: String

        var fractionCompleted: Double? {
            guard
                let currentFileIndex,
                let totalFileCount,
                totalFileCount > 0
            else {
                return nil
            }

            return min(Double(currentFileIndex) / Double(totalFileCount), 1)
        }
    }

    enum ProjectScanError: LocalizedError {
        case missingProjectFolder
        case missingInputFolder
        case missingSummary(URL)

        var errorDescription: String? {
            switch self {
            case .missingProjectFolder:
                Strings.ProjectScan.missingProjectFolder
            case .missingInputFolder:
                Strings.ProjectScan.missingInputFolder
            case .missingSummary(let url):
                String(format: Strings.ProjectScan.missingSummaryFormat, url.path)
            }
        }
    }

    /// Resolves a project folder and inventories files supported by the calling module.
    func scanInventory(
        project: Project,
        supportedFileExtensions: Set<String>,
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> ProjectScanInventory {
        AppLog.info("Starting scan for project '\(project.name)' (\(project.id.uuidString))")
        guard let projectRootURL = project.rootFolderURL else {
            AppLog.info("Scan failed before start: missing project folder bookmark")
            throw ProjectScanError.missingProjectFolder
        }

        guard let inputFolderURL = project.inputFolderURL else {
            AppLog.info("Scan failed before start: missing input folder bookmark")
            throw ProjectScanError.missingInputFolder
        }
        let displayInputFolderURL = project.rawInputFolderURL ?? inputFolderURL

        AppLog.info("Resolved project root: \(projectRootURL.path)")
        AppLog.info("Resolved input folder: \(inputFolderURL.path)")
        AppLog.info("Resolved raw input folder: \(displayInputFolderURL.path)")

        let inventory = try await Task.detached {
            try self.scanProjectFiles(
                supportedFileExtensions: supportedFileExtensions,
                projectRootURL: projectRootURL,
                inputFolderURL: inputFolderURL,
                displayInputFolderURL: displayInputFolderURL,
                recorderID: project.metadataSummaryValue ?? "",
                onProgress: onProgress
            )
        }.value

        AppLog.info("Scan inventoried \(inventory.files.count) files")
        return inventory
    }

    /// Builds and writes the shared scan summary after a module analyzes the inventory.
    func makeSummary(
        inventory: ProjectScanInventory,
        analyzedFiles: [ProjectScanFile],
        warnings: [String],
        attributes: [String: ScanAttributeValue] = [:]
    ) throws -> ProjectScanSummary {
        let summary = buildMediaSummary(
            inventory: inventory,
            files: analyzedFiles,
            warnings: warnings,
            attributes: attributes
        )
        try Self.writeSummary(summary, projectRootURL: inventory.projectRootURL)
        AppLog.scan("Native media scan complete")
        return summary
    }

    /// Loads the scan summary that was previously written into the project work folder.
    func loadSummary(for project: Project) throws -> ProjectScanSummary {
        AppLog.info("Loading scan summary for project '\(project.name)'")
        let loadedSummaryData: Data
        if let projectRootURL = project.rootFolderURL,
           let fileSummaryData = try? summaryData(projectRootURL: projectRootURL) {
            loadedSummaryData = fileSummaryData
        } else if let storedSummaryData = project.scanSummaryData {
            AppLog.scan("Using SwiftData scan summary snapshot for project '\(project.name)'")
            loadedSummaryData = storedSummaryData
        } else if project.rootFolderURL == nil {
            AppLog.info("Summary load failed: missing project folder bookmark and no SwiftData snapshot")
            throw ProjectScanError.missingProjectFolder
        } else {
            let summaryURL = project.rootFolderURL?
                .appendingPathComponent(ProjectFileNames.workDirectory)
                .appendingPathComponent(ProjectFileNames.scanSummary) ?? URL(fileURLWithPath: ProjectFileNames.scanSummary)
            AppLog.scan("Missing summary at \(summaryURL.path) and no SwiftData snapshot")
            throw ProjectScanError.missingSummary(summaryURL)
        }

        let summary = try decodeSummary(from: loadedSummaryData)
        AppLog.info("Loaded scan summary: \(summary.fileCount) files")
        return summary
    }

    nonisolated private func summaryData(projectRootURL: URL) throws -> Data {
        let accessedProject = projectRootURL.startAccessingSecurityScopedResource()
        AppLog.scan("Reading summary with project security scope=\(accessedProject)")
        defer {
            if accessedProject {
                projectRootURL.stopAccessingSecurityScopedResource()
            }
        }

        let rootSummaryURL = projectRootURL
            .appendingPathComponent(ProjectFileNames.scanSummary)
        let workSummaryURL = projectRootURL
            .appendingPathComponent(ProjectFileNames.workDirectory)
            .appendingPathComponent(ProjectFileNames.scanSummary)
        let summaryURL = FileManager.default.fileExists(atPath: workSummaryURL.path)
            ? workSummaryURL
            : rootSummaryURL

        guard FileManager.default.fileExists(atPath: summaryURL.path) else {
            AppLog.scan("Missing summary at \(summaryURL.path)")
            throw ProjectScanError.missingSummary(summaryURL)
        }

        AppLog.scan("Found summary at \(summaryURL.path)")
        return try Data(contentsOf: summaryURL)
    }

    nonisolated private func scanProjectFiles(
        supportedFileExtensions: Set<String>,
        projectRootURL: URL,
        inputFolderURL: URL,
        displayInputFolderURL: URL,
        recorderID: String,
        onProgress: @escaping @Sendable (Progress) -> Void
    ) throws -> ProjectScanInventory {
        let accessedProject = projectRootURL.startAccessingSecurityScopedResource()
        let accessedInput = inputFolderURL.startAccessingSecurityScopedResource()
        AppLog.scan("Native media scan security scope project=\(accessedProject) input=\(accessedInput)")

        defer {
            if accessedProject {
                projectRootURL.stopAccessingSecurityScopedResource()
            }

            if accessedInput {
                inputFolderURL.stopAccessingSecurityScopedResource()
            }
        }

        let mediaURLs = try supportedMediaURLs(in: inputFolderURL, supportedFileExtensions: supportedFileExtensions)
        onProgress(Progress(
            currentFileIndex: mediaURLs.isEmpty ? 0 : nil,
            totalFileCount: mediaURLs.count,
            currentFile: nil,
            message: mediaURLs.isEmpty
                ? Strings.ProjectScan.noSupportedFilesFound
                : String(format: Strings.ProjectScan.supportedFilesFoundFormat, mediaURLs.count)
        ))

        var files: [ProjectScanFileInfo] = []
        for (offset, url) in mediaURLs.enumerated() {
            let index = offset + 1
            let relativePath = relativePath(for: url, inputFolderURL: inputFolderURL)
            AppLog.scan("Scanning file \(index)/\(mediaURLs.count): \(relativePath)")
            onProgress(Progress(
                currentFileIndex: index,
                totalFileCount: mediaURLs.count,
                currentFile: relativePath,
                message: String(format: Strings.ProjectScan.scanningFileFormat, index, mediaURLs.count)
            ))

            files.append(fileInfo(for: url, inputFolderURL: inputFolderURL))
        }

        return ProjectScanInventory(
            projectRootURL: projectRootURL,
            inputFolderURL: inputFolderURL,
            displayInputFolderURL: displayInputFolderURL,
            recorderID: recorderID,
            files: files
        )
    }

    nonisolated private func supportedMediaURLs(
        in inputFolderURL: URL,
        supportedFileExtensions: Set<String>
    ) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: inputFolderURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                let values = try? url.resourceValues(forKeys: resourceKeys)
                let isSupportedFile = values?.isRegularFile == true ||
                    (values?.isSymbolicLink == true && FileManager.default.fileExists(atPath: url.resolvingSymlinksInPath().path))
                return isSupportedFile &&
                    supportedFileExtensions.contains(url.pathExtension.lowercased()) &&
                    !isGeneratedProjectArtifact(url, inputFolderURL: inputFolderURL)
            }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    nonisolated private func isGeneratedProjectArtifact(_ url: URL, inputFolderURL: URL) -> Bool {
        let generatedFolders = GeneratedProjectArtifacts.folderNames
        let inputFolderPath = inputFolderURL.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        let inputFolderIsProjectSource = inputFolderURL.lastPathComponent == ProjectFileNames.sourceDirectory
        return url.pathComponents.contains { component in
            if inputFolderIsProjectSource,
               component == ProjectFileNames.sourceDirectory,
               urlPath.hasPrefix(inputFolderPath + "/") {
                return false
            }
            return generatedFolders.contains(component.lowercased())
        }
    }

    nonisolated private func buildMediaSummary(
        inventory: ProjectScanInventory,
        files: [ProjectScanFile],
        warnings: [String],
        attributes: [String: ScanAttributeValue]
    ) -> ProjectScanSummary {
        let readableFiles = files.filter(\.readable)
        let durations = readableFiles.compactMap(\.durationSeconds)
        let totalSizeBytes = files.reduce(0) { $0 + $1.sizeBytes }

        return ProjectScanSummary(
            projectName: inventory.projectRootURL.lastPathComponent,
            recorderID: inventory.recorderID,
            inputFolder: inventory.displayInputFolderURL.path,
            scannedAt: .now,
            fileCount: files.count,
            readableFileCount: readableFiles.count,
            unreadableFileCount: files.count - readableFiles.count,
            totalSizeBytes: totalSizeBytes,
            durationMinSeconds: durations.min(),
            durationMaxSeconds: durations.max(),
            durationModeSeconds: roundMostCommon(durations),
            formats: sortedUnique(readableFiles.compactMap(\.format)),
            qualityWarningCount: files.filter { $0.qualityFlag != "OK" }.count,
            warnings: warnings,
            attributes: attributes,
            files: files
        )
    }

    nonisolated static func writeSummary(_ summary: ProjectScanSummary, projectRootURL: URL) throws {
        let workURL = projectRootURL.appendingPathComponent(ProjectFileNames.workDirectory)
        try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)

        let data = try encodedSummaryData(summary)
        try data.write(to: workURL.appendingPathComponent(ProjectFileNames.scanSummary), options: .atomic)
    }

    nonisolated static func encodedSummaryData(_ summary: ProjectScanSummary) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(summary)
    }

    private func decodeSummary(from data: Data) throws -> ProjectScanSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectScanSummary.self, from: data)
    }

    nonisolated private func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            let targetValues = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey])
            if let targetSize = targetValues?.fileSize {
                return targetSize
            }
        }

        return values?.fileSize ?? 0
    }

    nonisolated private func relativePath(for url: URL, inputFolderURL: URL) -> String {
        let inputPath = inputFolderURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(inputPath) else {
            return url.lastPathComponent
        }

        return String(filePath.dropFirst(inputPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    nonisolated private func fileInfo(for url: URL, inputFolderURL: URL) -> ProjectScanFileInfo {
        ProjectScanFileInfo(
            url: url,
            inputFolderURL: inputFolderURL,
            fileName: url.lastPathComponent,
            relativePath: relativePath(for: url, inputFolderURL: inputFolderURL),
            sizeBytes: fileSize(url),
            format: url.pathExtension.uppercased()
        )
    }

    nonisolated private func roundMostCommon(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var counts: [Double: Int] = [:]
        for value in values {
            let rounded = value.rounded()
            counts[rounded, default: 0] += 1
        }
        return counts.max { $0.value < $1.value }?.key
    }

    nonisolated private func sortedUnique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    nonisolated private func sortedUniqueInts(_ values: [Int]) -> [Int] {
        Array(Set(values)).sorted()
    }
}
