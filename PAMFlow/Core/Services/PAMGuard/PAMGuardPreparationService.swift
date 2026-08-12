//
//  PAMGuardPreparationService.swift
//  PAMFlow
//
//  Created by Dory on 27/06/2026.
//

import Darwin
import Foundation

/// PAMGuard template/package preparation boundary.
@MainActor
protocol PAMGuardPreparationServicing {
    func prepare(
        project: Project,
        scanSummary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        target: PAMGuardPreparationService.DetectionTarget
    ) throws -> PAMGuardPreparationService.Result
}

/// Creates the project-side PAMGuard folder layout and copies the selected template unchanged.
final class PAMGuardPreparationService: PAMGuardPreparationServicing {
    enum DetectionTarget: String, CaseIterable, Identifiable {
        case pygmyKillerWhales
        case generalOdontocetes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .pygmyKillerWhales:
                Strings.PAMGuardSetup.pygmyKillerWhales
            case .generalOdontocetes:
                Strings.PAMGuardSetup.generalOdontocetes
            }
        }
    }

    struct Result: Equatable {
        let templateURL: URL
        let linkedInputCount: Int
    }

    enum PreparationError: LocalizedError {
        case missingProjectFolder
        case missingInputFolder
        case missingTemplate
        case noAuditedInputFiles
        case inputSymlinkFailed(String)
        case databaseCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingProjectFolder:
                Strings.PAMGuardPreparationError.missingProjectFolder
            case .missingInputFolder:
                Strings.PAMGuardPreparationError.missingInputFolder
            case .missingTemplate:
                Strings.PAMGuardPreparationError.missingTemplate
            case .noAuditedInputFiles:
                Strings.PAMGuardPreparationError.noAuditedInputFiles
            case .inputSymlinkFailed(let message):
                String(format: Strings.PAMGuardPreparationError.inputSymlinkFailedFormat, message)
            case .databaseCreationFailed(let message):
                String(format: Strings.PAMGuardPreparationError.databaseCreationFailedFormat, message)
            }
        }
    }

    func prepare(
        project: Project,
        scanSummary: ProjectScanSummary,
        decisions: [ManualAuditDecision],
        target: DetectionTarget
    ) throws -> Result {
        guard let projectRootURL = project.rootFolderURL else {
            throw PreparationError.missingProjectFolder
        }
        guard let sourceInputURL = project.inputFolderURL else {
            throw PreparationError.missingInputFolder
        }

        let accessedProject = projectRootURL.startAccessingSecurityScopedResource()
        let accessedInput = sourceInputURL.startAccessingSecurityScopedResource()
        defer {
            if accessedProject { projectRootURL.stopAccessingSecurityScopedResource() }
            if accessedInput { sourceInputURL.stopAccessingSecurityScopedResource() }
        }

        let pamguardURL = projectRootURL.appendingPathComponent(ProjectFileNames.pamguardDirectory)
        let dbURL = pamguardURL.appendingPathComponent("db")
        let binaryURL = pamguardURL.appendingPathComponent("binary")
        let inputURL = pamguardURL.appendingPathComponent("input")
        let legacyBinaryURL = pamguardURL.appendingPathComponent("PAMBinary")

        try removeDirectoryIfPresent(at: legacyBinaryURL)
        try createCleanDirectory(at: dbURL)
        try createCleanDirectory(at: binaryURL)
        try createCleanDirectory(at: inputURL)

        let selectedFiles = selectedInputFiles(
            from: scanSummary.files,
            decisions: decisions,
            sourceInputURL: sourceInputURL
        )
        guard !selectedFiles.isEmpty else {
            throw PreparationError.noAuditedInputFiles
        }

        for sourceURL in selectedFiles {
            let destinationURL = inputURL.appendingPathComponent(sourceURL.lastPathComponent)
            try linkOrCopyFile(from: sourceURL, to: destinationURL)
        }
        let databaseURL = dbURL.appendingPathComponent("db.sqlite")
        try createEmptySQLiteDatabase(at: databaseURL)

        let templateURL = try copiedTemplate(
            projectName: project.name,
            target: target,
            outputFolderURL: pamguardURL
        )

        return Result(templateURL: templateURL, linkedInputCount: selectedFiles.count)
    }

    private func selectedInputFiles(
        from files: [ProjectScanFile],
        decisions: [ManualAuditDecision],
        sourceInputURL: URL
    ) -> [URL] {
        let decisionByPath = Dictionary(uniqueKeysWithValues: decisions.map { ($0.fileRelativePath, $0.decision) })
        return files.compactMap { file in
            guard let decision = decisionByPath[file.relativePath],
                  decision == .valid || decision == .unsure else {
                return nil
            }

            return sourceInputURL.appendingPathComponent(file.relativePath)
        }
    }

    private func createCleanDirectory(at url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func removeDirectoryIfPresent(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func linkOrCopyFile(from sourceURL: URL, to destinationURL: URL) throws {
        do {
            try FileManager.default.createSymbolicLink(
                at: destinationURL,
                withDestinationURL: sourceURL
            )
        } catch {
            throw PreparationError.inputSymlinkFailed(error.localizedDescription)
        }
    }

    private func createEmptySQLiteDatabase(at url: URL) throws {
        typealias SQLiteOpen = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<OpaquePointer?>) -> Int32
        typealias SQLiteExec = @convention(c) (
            OpaquePointer?,
            UnsafePointer<CChar>,
            OpaquePointer?,
            OpaquePointer?,
            UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?
        ) -> Int32
        typealias SQLiteClose = @convention(c) (OpaquePointer?) -> Int32
        typealias SQLiteFree = @convention(c) (UnsafeMutableRawPointer?) -> Void

        guard let library = dlopen("/usr/lib/libsqlite3.dylib", RTLD_NOW) else {
            throw PreparationError.databaseCreationFailed(String(cString: dlerror()))
        }
        defer { dlclose(library) }

        guard let openSymbol = dlsym(library, "sqlite3_open"),
              let execSymbol = dlsym(library, "sqlite3_exec"),
              let closeSymbol = dlsym(library, "sqlite3_close"),
              let freeSymbol = dlsym(library, "sqlite3_free") else {
            throw PreparationError.databaseCreationFailed(Strings.PAMGuardPreparationError.sqliteSymbolsMissing)
        }

        let sqliteOpen = unsafeBitCast(openSymbol, to: SQLiteOpen.self)
        let sqliteExec = unsafeBitCast(execSymbol, to: SQLiteExec.self)
        let sqliteClose = unsafeBitCast(closeSymbol, to: SQLiteClose.self)
        let sqliteFree = unsafeBitCast(freeSymbol, to: SQLiteFree.self)

        var database: OpaquePointer?
        let openResult = url.path.withCString { sqliteOpen($0, &database) }
        guard openResult == 0 else {
            if database != nil { _ = sqliteClose(database) }
            throw PreparationError.databaseCreationFailed(String(format: Strings.PAMGuardPreparationError.sqliteOpenFailedFormat, openResult))
        }
        defer { _ = sqliteClose(database) }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let execResult = "PRAGMA user_version = 0;".withCString {
            sqliteExec(database, $0, nil, nil, &errorMessage)
        }
        guard execResult == 0 else {
            let message = errorMessage.map { String(cString: $0) } ?? String(format: Strings.PAMGuardPreparationError.sqliteInitializationFailedFormat, execResult)
            if errorMessage != nil { sqliteFree(errorMessage) }
            throw PreparationError.databaseCreationFailed(message)
        }
    }

    private func copiedTemplate(
        projectName: String,
        target: DetectionTarget,
        outputFolderURL: URL
    ) throws -> URL {
        guard let bundledTemplateURL = Bundle.main.url(
            forResource: "template",
            withExtension: "psfx"
        ) else {
            throw PreparationError.missingTemplate
        }

        let outputURL = outputFolderURL.appendingPathComponent("\(projectName)-\(target.rawValue).psfx")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.copyItem(at: bundledTemplateURL, to: outputURL)
        return outputURL
    }

}
