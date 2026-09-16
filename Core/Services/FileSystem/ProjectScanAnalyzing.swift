//
//  ProjectScanAnalyzing.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Common file values discovered by the shared project scanner before module-specific analysis.
public struct ProjectScanFileInfo: Sendable {
    /// Absolute URL for the discovered source file.
    public let url: URL
    /// Root folder used to calculate the file's relative path.
    public let inputFolderURL: URL
    /// Display name of the discovered source file.
    public let fileName: String
    /// Path from the selected input folder to the discovered file.
    public let relativePath: String
    /// File size in bytes, resolving symbolic links when needed.
    public let sizeBytes: Int
    /// Uppercased file extension used in persisted scan summaries.
    public let format: String
}

/// File inventory produced by Core before a feature module performs media-specific analysis.
public struct ProjectScanInventory: Sendable {
    /// Security-scoped project root used for writing the scan summary.
    public let projectRootURL: URL
    /// Input folder selected for scanning.
    public let inputFolderURL: URL
    /// User-facing input folder path preserved in the summary.
    public let displayInputFolderURL: URL
    /// Optional recorder identifier copied from generic project metadata.
    public let recorderID: String
    /// Files discovered by Core using the module's supported extension list.
    public let files: [ProjectScanFileInfo]
}

/// Module-owned analysis for files discovered by the shared scanner.
public protocol ProjectScanAnalyzing: Sendable {
    /// Converts one discovered file into a persisted scan record.
    nonisolated func analyzeFile(_ fileInfo: ProjectScanFileInfo) async -> ProjectScanFile
    /// Builds module-owned summary attributes from analyzed scan records.
    nonisolated func summaryAttributes(files: [ProjectScanFile]) -> [String: ScanAttributeValue]
    /// Builds user-facing warnings from the module-specific scan records.
    nonisolated func warnings(files: [ProjectScanFile], totalSizeBytes: Int) -> [String]
}

public extension ProjectScanAnalyzing {
    nonisolated func summaryAttributes(files: [ProjectScanFile]) -> [String: ScanAttributeValue] {
        [:]
    }
}

/// Builds generic fallback scan records for unreadable module files.
public enum ProjectScanFileFactory {
    /// Creates a persisted scan record for a file whose module-specific metadata could not be read.
    public nonisolated static func unreadableFile(_ fileInfo: ProjectScanFileInfo, message: String) -> ProjectScanFile {
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
