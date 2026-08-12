//
//  ProjectFileService.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation

/// File-system project creation and cleanup operations needed by feature models.
@MainActor
protocol ProjectFileServicing {
    func createProject(
        named projectName: String,
        inputSelection: ProjectInputSourceSelection,
        moduleID: String
    ) throws -> Project

    func createProject(
        named projectName: String,
        inputSelection: ProjectInputSourceSelection,
        moduleID: String,
        projectContainerURL: URL
    ) throws -> Project

    func suggestedProjectName(from inputFolderURL: URL, module: WorkflowModule) -> String
    func deleteProjectFolder(for project: Project) throws
    func removeTemporaryArtifacts(for project: Project) throws
}

/// Creates PAMFlow project folders and security-scoped bookmarks.
///
/// This service owns file-system setup only. It does not persist project
/// metadata and does not update UI state.
final class ProjectFileService: ProjectFileServicing {
    enum ProjectFileError: LocalizedError {
        case failedToAccessFolder(URL)
        case failedToAccessFile(URL)
        case failedToCreateProjectFolder(URL, Error)
        case failedToCreateBookmark(URL, Error)

        var errorDescription: String? {
            switch self {
            case .failedToAccessFolder(let url):
                return "Could not access \(url.path)."

            case .failedToAccessFile(let url):
                return "Could not access \(url.path)."

            case .failedToCreateProjectFolder(let url, let error):
                return "Could not create project folder at \(url.path). \(error.localizedDescription)"

            case .failedToCreateBookmark(let url, let error):
                return "Could not create folder bookmark for \(url.path). \(error.localizedDescription)"
            }
        }
    }

    func createProject(
        named projectName: String,
        inLibraryFolder libraryURL: URL,
        fromInputFolder inputFolderURL: URL,
        moduleID: String,
        recorderID: String?
    ) throws -> Project {
        try createProject(
            named: projectName,
            inputSelection: .folder(inputFolderURL),
            moduleID: moduleID
        )
    }

    func createProject(
        named projectName: String,
        inLibraryFolder libraryURL: URL,
        inputSelection: ProjectInputSourceSelection,
        moduleID: String
    ) throws -> Project {
        try createProject(
            named: projectName,
            inputSelection: inputSelection,
            moduleID: moduleID
        )
    }

    func createProject(
        named projectName: String,
        inputSelection: ProjectInputSourceSelection,
        moduleID: String
    ) throws -> Project {
        try createProject(
            named: projectName,
            inputSelection: inputSelection,
            moduleID: moduleID,
            projectContainerCandidates: projectContainerCandidates(for: inputSelection)
        )
    }

    func createProject(
        named projectName: String,
        inputSelection: ProjectInputSourceSelection,
        moduleID: String,
        projectContainerURL: URL
    ) throws -> Project {
        try createProject(
            named: projectName,
            inputSelection: inputSelection,
            moduleID: moduleID,
            projectContainerCandidates: [projectContainerURL]
        )
    }

    private func createProject(
        named projectName: String,
        inputSelection: ProjectInputSourceSelection,
        moduleID: String,
        projectContainerCandidates: [URL]
    ) throws -> Project {
        let accessedInputURLs = startAccessingInputSelection(inputSelection)

        defer {
            stopAccessingInputURLs(accessedInputURLs)
        }

        let moduleProjectName = sanitizeProjectName(projectName)
        var lastProjectRootURL: URL?
        var lastError: Error?

        for projectContainerURL in projectContainerCandidates.uniqueStandardizedURLs() {
            AppLog.info("Trying project container \(projectContainerURL.path)")
            let accessedContainer = projectContainerURL.startAccessingSecurityScopedResource()
            defer {
                if accessedContainer {
                    projectContainerURL.stopAccessingSecurityScopedResource()
                }
            }

            let sanitizedProjectName = nextUniqueProjectName(
                baseName: moduleProjectName,
                in: projectContainerURL
            )
            let projectRootURL = projectContainerURL
                .appendingPathComponent(sanitizedProjectName)
            lastProjectRootURL = projectRootURL

            do {
                try FileManager.default.createDirectory(
                    at: projectRootURL,
                    withIntermediateDirectories: true
                )
                AppLog.info("Created project folder at \(projectRootURL.path)")

                try createProjectSubfolders(in: projectRootURL, moduleID: moduleID)
                let inputFolderURL = try prepareInputSource(
                    inputSelection,
                    projectRootURL: projectRootURL
                )
                let rawInputFolderURL = rawInputFolder(for: inputSelection)

                return Project(
                    name: sanitizedProjectName,
                    moduleID: moduleID,
                    rootFolderBookmark: try makeBookmark(for: projectRootURL),
                    inputFolderBookmark: try makeBookmark(for: inputFolderURL),
                    rawInputFolderBookmark: try makeBookmark(for: rawInputFolderURL)
                )
            } catch let error as ProjectFileError {
                lastError = error
                AppLog.info("Project folder candidate failed: \(projectContainerURL.path) - \(error.localizedDescription)")
            } catch {
                lastError = error
                AppLog.info("Project folder candidate failed: \(projectContainerURL.path) - \(error.localizedDescription)")
            }
        }

        let failedURL = lastProjectRootURL ?? projectContainerCandidates[0]
            .appendingPathComponent(moduleProjectName)
        throw ProjectFileError.failedToCreateProjectFolder(
            failedURL,
            lastError ?? CocoaError(.fileWriteNoPermission)
        )
    }

    private func projectContainerCandidates(for inputSelection: ProjectInputSourceSelection) -> [URL] {
        switch inputSelection {
        case .folder(let url):
            return [
                url,
                url.deletingLastPathComponent()
            ].uniqueStandardizedURLs()
        case .files(let urls):
            return [
                urls.first?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
            ].uniqueStandardizedURLs()
        }
    }

    private func prepareInputSource(
        _ inputSelection: ProjectInputSourceSelection,
        projectRootURL: URL
    ) throws -> URL {
        switch inputSelection {
        case .folder(let url):
            return url

        case .files(let urls):
            let sourceURL = projectRootURL.appendingPathComponent(ProjectFileNames.sourceDirectory)
            try FileManager.default.createDirectory(
                at: sourceURL,
                withIntermediateDirectories: true
            )

            for url in urls {
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ProjectFileError.failedToAccessFile(url)
                }
                let destinationURL = uniqueLinkURL(for: url, in: sourceURL)
                try linkLargeInputFile(from: url, to: destinationURL)
            }

            return sourceURL
        }
    }

    private func rawInputFolder(for inputSelection: ProjectInputSourceSelection) -> URL {
        inputSelection.rawMediaFolderURL ?? FileManager.default.homeDirectoryForCurrentUser
    }

    func suggestedProjectName(from inputFolderURL: URL, module: WorkflowModule) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return "PAMFlow_\(module.projectNamePrefix)_\(formatter.string(from: Date()))"
    }

    private func createProjectSubfolders(in rootURL: URL, moduleID: String) throws {
        var folders = [ProjectFileNames.workDirectory]
        if WorkflowModule.module(for: moduleID).usesPAMGuard {
            folders.append(ProjectFileNames.pamguardDirectory)
        }

        for folder in folders {
            try FileManager.default.createDirectory(
                at: rootURL.appendingPathComponent(folder),
                withIntermediateDirectories: true
            )
        }
    }

    private func startAccessingInputSelection(_ inputSelection: ProjectInputSourceSelection) -> [URL] {
        switch inputSelection {
        case .folder(let url):
            return url.startAccessingSecurityScopedResource() ? [url] : []
        case .files(let urls):
            return urls.filter { $0.startAccessingSecurityScopedResource() }
        }
    }

    private func stopAccessingInputURLs(_ urls: [URL]) {
        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw ProjectFileError.failedToCreateBookmark(url, error)
        }
    }

    private func sanitizeProjectName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)

        let sanitized = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? "Untitled Project" : sanitized
    }

    private func nextUniqueProjectName(baseName: String, in folderURL: URL) -> String {
        let sanitizedBaseName = sanitizeProjectName(baseName)
        let sequenceKey = projectNameSequenceKey(baseName: sanitizedBaseName, in: folderURL)
        var suffix = UserDefaults.standard.integer(forKey: sequenceKey)
        var candidate = suffix == 0 ? sanitizedBaseName : "\(sanitizedBaseName)_\(suffix)"

        while FileManager.default.fileExists(atPath: folderURL.appendingPathComponent(candidate).path) {
            suffix += 1
            candidate = "\(sanitizedBaseName)_\(suffix)"
        }

        UserDefaults.standard.set(suffix + 1, forKey: sequenceKey)
        return candidate
    }

    private func projectNameSequenceKey(baseName: String, in folderURL: URL) -> String {
        "PAMFlow.projectNameSequence.\(folderURL.standardizedFileURL.path).\(baseName)"
    }

    private func uniqueLinkURL(for sourceURL: URL, in folderURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let pathExtension = sourceURL.pathExtension
        var candidate = folderURL.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 1

        while FileManager.default.fileExists(atPath: candidate.path) {
            let fileName = pathExtension.isEmpty
                ? "\(baseName)_\(suffix)"
                : "\(baseName)_\(suffix).\(pathExtension)"
            candidate = folderURL.appendingPathComponent(fileName)
            suffix += 1
        }

        return candidate
    }

    private func linkLargeInputFile(from sourceURL: URL, to destinationURL: URL) throws {
        do {
            try FileManager.default.linkItem(at: sourceURL, to: destinationURL)
        } catch {
            try FileManager.default.createSymbolicLink(
                at: destinationURL,
                withDestinationURL: sourceURL
            )
        }
    }

    func deleteProjectFolder(for project: Project) throws {
        guard let rootFolderURL = project.rootFolderURL else { return }

        let accessed = rootFolderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                rootFolderURL.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: rootFolderURL.path) {
            try FileManager.default.removeItem(at: rootFolderURL)
        }
    }

    func removeTemporaryArtifacts(for project: Project) throws {
        guard let rootFolderURL = project.rootFolderURL else { return }

        let accessed = rootFolderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                rootFolderURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let temporaryURLs = [
            rootFolderURL.appendingPathComponent(ProjectFileNames.workDirectory, isDirectory: true),
            rootFolderURL.appendingPathComponent(ProjectFileNames.scanSummary),
            rootFolderURL
                .appendingPathComponent(ProjectFileNames.detectionsDirectory, isDirectory: true)
                .appendingPathComponent(ProjectFileNames.sharkTrackManifest)
        ]

        for url in temporaryURLs where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
