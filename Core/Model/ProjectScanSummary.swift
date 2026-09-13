//
//  ProjectScanSummary.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Foundation

/// Codable value stored in scan-level and file-level extension attributes.
///
/// Core treats these values as opaque. Feature modules own the keys and typed
/// accessors for media-specific scan data.
nonisolated enum ScanAttributeValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case strings([String])
    case ints([Int])
    case doubles([Double])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([Int].self) {
            self = .ints(value)
        } else if let value = try? container.decode([Double].self) {
            self = .doubles(value)
        } else {
            self = try .strings(container.decode([String].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .strings(let value):
            try container.encode(value)
        case .ints(let value):
            try container.encode(value)
        case .doubles(let value):
            try container.encode(value)
        }
    }

    /// Stable text representation used by generic search and diagnostics.
    nonisolated var searchText: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .bool(let value):
            return String(value)
        case .strings(let values):
            return values.joined(separator: " ")
        case .ints(let values):
            return values.map { String($0) }.joined(separator: " ")
        case .doubles(let values):
            return values.map { String($0) }.joined(separator: " ")
        }
    }
}

extension Dictionary where Key == String, Value == ScanAttributeValue {
    nonisolated func string(_ key: String) -> String? {
        if case .string(let value) = self[key] { return value }
        return nil
    }

    nonisolated func int(_ key: String) -> Int? {
        if case .int(let value) = self[key] { return value }
        return nil
    }

    nonisolated func double(_ key: String) -> Double? {
        if case .double(let value) = self[key] { return value }
        if case .int(let value) = self[key] { return Double(value) }
        return nil
    }

    nonisolated func bool(_ key: String) -> Bool? {
        if case .bool(let value) = self[key] { return value }
        return nil
    }

    nonisolated func strings(_ key: String) -> [String]? {
        if case .strings(let value) = self[key] { return value }
        return nil
    }

    nonisolated func ints(_ key: String) -> [Int]? {
        if case .ints(let value) = self[key] { return value }
        return nil
    }
}

/// Technical scan output shared by every module.
nonisolated struct ProjectScanSummary: Codable, Equatable, Sendable {
    var projectName: String
    var recorderID: String?
    var inputFolder: String
    var scannedAt: Date?
    var fileCount: Int
    var readableFileCount: Int
    var unreadableFileCount: Int
    var totalSizeBytes: Int
    var durationMinSeconds: Double?
    var durationMaxSeconds: Double?
    var durationModeSeconds: Double?
    var formats: [String]?
    var qualityWarningCount: Int
    var warnings: [String]
    var attributes: [String: ScanAttributeValue]
    var files: [ProjectScanFile]
}

/// Technical scan output shared by every scanned source or generated review item.
nonisolated struct ProjectScanFile: Codable, Equatable, Identifiable, Sendable {
    var id: String { relativePath }

    var fileName: String
    var relativePath: String
    var sizeBytes: Int
    var readable: Bool
    var readError: String
    var durationSeconds: Double?
    var format: String?
    var qualityFlag: String
    var qualityReasons: [String]
    var attributes: [String: ScanAttributeValue]
}

extension ProjectScanSummary {
    enum CodingKeys: String, CodingKey {
        case projectName = "project_name"
        case recorderID = "recorder_id"
        case inputFolder = "input_folder"
        case scannedAt = "scanned_at"
        case fileCount = "file_count"
        case readableFileCount = "readable_file_count"
        case unreadableFileCount = "unreadable_file_count"
        case totalSizeBytes = "total_size_bytes"
        case durationMinSeconds = "duration_min_seconds"
        case durationMaxSeconds = "duration_max_seconds"
        case durationModeSeconds = "duration_mode_seconds"
        case formats
        case qualityWarningCount = "quality_warning_count"
        case warnings
        case attributes
        case files
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectName = try container.decode(String.self, forKey: .projectName)
        recorderID = try container.decodeIfPresent(String.self, forKey: .recorderID)
        inputFolder = try container.decode(String.self, forKey: .inputFolder)
        scannedAt = try container.decodeIfPresent(Date.self, forKey: .scannedAt)
        fileCount = try container.decode(Int.self, forKey: .fileCount)
        readableFileCount = try container.decode(Int.self, forKey: .readableFileCount)
        unreadableFileCount = try container.decode(Int.self, forKey: .unreadableFileCount)
        totalSizeBytes = try container.decode(Int.self, forKey: .totalSizeBytes)
        durationMinSeconds = try container.decodeIfPresent(Double.self, forKey: .durationMinSeconds)
        durationMaxSeconds = try container.decodeIfPresent(Double.self, forKey: .durationMaxSeconds)
        durationModeSeconds = try container.decodeIfPresent(Double.self, forKey: .durationModeSeconds)
        formats = try container.decodeIfPresent([String].self, forKey: .formats)
        qualityWarningCount = try container.decode(Int.self, forKey: .qualityWarningCount)
        warnings = try container.decode([String].self, forKey: .warnings)
        attributes = try container.decodeIfPresent([String: ScanAttributeValue].self, forKey: .attributes) ?? [:]
        files = try container.decode([ProjectScanFile].self, forKey: .files)
    }
}

extension ProjectScanFile {
    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case relativePath = "relative_path"
        case sizeBytes = "size_bytes"
        case readable
        case readError = "read_error"
        case durationSeconds = "duration_seconds"
        case format
        case qualityFlag = "quality_flag"
        case qualityReasons = "quality_reasons"
        case attributes
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try container.decode(String.self, forKey: .fileName)
        relativePath = try container.decode(String.self, forKey: .relativePath)
        sizeBytes = try container.decode(Int.self, forKey: .sizeBytes)
        readable = try container.decode(Bool.self, forKey: .readable)
        readError = try container.decode(String.self, forKey: .readError)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        format = try container.decodeIfPresent(String.self, forKey: .format)
        qualityFlag = try container.decode(String.self, forKey: .qualityFlag)
        qualityReasons = try container.decode([String].self, forKey: .qualityReasons)
        attributes = try container.decodeIfPresent([String: ScanAttributeValue].self, forKey: .attributes) ?? [:]
    }
}
