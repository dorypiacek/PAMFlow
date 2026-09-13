//
//  ProjectScanAnalyzing.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Common file values discovered by the shared project scanner before module-specific analysis.
struct ProjectScanFileInfo: Sendable {
    /// Absolute URL for the discovered source file.
    let url: URL
    /// Root folder used to calculate the file's relative path.
    let inputFolderURL: URL
    /// Display name of the discovered source file.
    let fileName: String
    /// Path from the selected input folder to the discovered file.
    let relativePath: String
    /// File size in bytes, resolving symbolic links when needed.
    let sizeBytes: Int
    /// Uppercased file extension used in persisted scan summaries.
    let format: String
}

/// File inventory produced by Core before a feature module performs media-specific analysis.
struct ProjectScanInventory: Sendable {
    /// Security-scoped project root used for writing the scan summary.
    let projectRootURL: URL
    /// Input folder selected for scanning.
    let inputFolderURL: URL
    /// User-facing input folder path preserved in the summary.
    let displayInputFolderURL: URL
    /// Optional recorder identifier copied from generic project metadata.
    let recorderID: String
    /// Files discovered by Core using the module's supported extension list.
    let files: [ProjectScanFileInfo]
}

/// Module-owned analysis for files discovered by the shared scanner.
protocol ProjectScanAnalyzing: Sendable {
    /// Converts one discovered file into a persisted scan record.
    nonisolated func analyzeFile(_ fileInfo: ProjectScanFileInfo) async -> ProjectScanFile
    /// Builds module-owned summary attributes from analyzed scan records.
    nonisolated func summaryAttributes(files: [ProjectScanFile]) -> [String: ScanAttributeValue]
    /// Builds user-facing warnings from the module-specific scan records.
    nonisolated func warnings(files: [ProjectScanFile], totalSizeBytes: Int) -> [String]
}

extension ProjectScanAnalyzing {
    nonisolated func summaryAttributes(files: [ProjectScanFile]) -> [String: ScanAttributeValue] {
        [:]
    }
}

/// Builds generic fallback scan records for unreadable module files.
enum ProjectScanFileFactory {
    /// Creates a persisted scan record for a file whose module-specific metadata could not be read.
    nonisolated static func unreadableFile(_ fileInfo: ProjectScanFileInfo, message: String) -> ProjectScanFile {
        ProjectScanFile(
            fileName: fileInfo.fileName,
            relativePath: fileInfo.relativePath,
            sizeBytes: fileInfo.sizeBytes,
            readable: false,
            readError: message,
            durationSeconds: nil,
            format: fileInfo.format,
            qualityFlag: ProjectQuality.check,
            qualityReasons: [ProjectQuality.readError],
            attributes: [:]
        )
    }
}
