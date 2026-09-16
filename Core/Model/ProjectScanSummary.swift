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
public nonisolated enum ScanAttributeValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case strings([String])
    case ints([Int])
    case doubles([Double])

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
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
    public nonisolated var searchText: String {
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

public extension Dictionary where Key == String, Value == ScanAttributeValue {
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
public nonisolated struct ProjectScanSummary: Codable, Equatable, Sendable {
    public var projectName: String
    public var recorderID: String?
    public var inputFolder: String
    public var scannedAt: Date?
    public var fileCount: Int
    public var readableFileCount: Int
    public var unreadableFileCount: Int
    public var totalSizeBytes: Int
    public var durationMinSeconds: Double?
    public var durationMaxSeconds: Double?
    public var durationModeSeconds: Double?
    public var formats: [String]?
    public var qualityWarningCount: Int
    public var warnings: [String]
    public var attributes: [String: ScanAttributeValue]
    public var files: [ProjectScanFile]

    public init(
        projectName: String,
        recorderID: String?,
        inputFolder: String,
        scannedAt: Date?,
        fileCount: Int,
        readableFileCount: Int,
        unreadableFileCount: Int,
        totalSizeBytes: Int,
        durationMinSeconds: Double?,
        durationMaxSeconds: Double?,
        durationModeSeconds: Double?,
        formats: [String]?,
        qualityWarningCount: Int,
        warnings: [String],
        attributes: [String: ScanAttributeValue] = [:],
        files: [ProjectScanFile]
    ) {
        self.projectName = projectName
        self.recorderID = recorderID
        self.inputFolder = inputFolder
        self.scannedAt = scannedAt
        self.fileCount = fileCount
        self.readableFileCount = readableFileCount
        self.unreadableFileCount = unreadableFileCount
        self.totalSizeBytes = totalSizeBytes
        self.durationMinSeconds = durationMinSeconds
        self.durationMaxSeconds = durationMaxSeconds
        self.durationModeSeconds = durationModeSeconds
        self.formats = formats
        self.qualityWarningCount = qualityWarningCount
        self.warnings = warnings
        self.attributes = attributes
        self.files = files
    }
}

/// Technical scan output shared by every scanned source or generated review item.
public nonisolated struct ProjectScanFile: Codable, Equatable, Identifiable, Sendable {
    public var id: String { relativePath }

    public var fileName: String
    public var relativePath: String
    public var sizeBytes: Int
    public var readable: Bool
    public var readError: String
    public var durationSeconds: Double?
    public var format: String?
    public var qualityFlag: String
    public var qualityReasons: [String]
    public var attributes: [String: ScanAttributeValue]

    public init(
        fileName: String,
        relativePath: String,
        sizeBytes: Int,
        readable: Bool,
        readError: String,
        durationSeconds: Double?,
        format: String?,
        qualityFlag: String,
        qualityReasons: [String],
        attributes: [String: ScanAttributeValue] = [:]
    ) {
        self.fileName = fileName
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.readable = readable
        self.readError = readError
        self.durationSeconds = durationSeconds
        self.format = format
        self.qualityFlag = qualityFlag
        self.qualityReasons = qualityReasons
        self.attributes = attributes
    }
}

public extension ProjectScanSummary {
    enum CodingKeys: String, CodingKey, CaseIterable {
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
        attributes.merge(try Self.legacyAttributes(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))) { current, _ in current }
        files = try container.decode([ProjectScanFile].self, forKey: .files)
    }
}

public extension ProjectScanFile {
    enum CodingKeys: String, CodingKey, CaseIterable {
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
        attributes.merge(try Self.legacyAttributes(from: decoder, excluding: CodingKeys.allCases.map(\.stringValue))) { current, _ in current }
    }
}

private extension Decodable {
    nonisolated static func legacyAttributes(from decoder: Decoder, excluding excludedKeys: [String]) throws -> [String: ScanAttributeValue] {
        let excludedKeys = Set(excludedKeys)
        let container = try decoder.container(keyedBy: LegacyScanAttributeKey.self)

        return container.allKeys.reduce(into: [String: ScanAttributeValue]()) { attributes, key in
            guard !excludedKeys.contains(key.stringValue),
                  let value = try? container.decode(ScanAttributeValue.self, forKey: key) else {
                return
            }
            attributes[key.stringValue] = value
        }
    }
}

private struct LegacyScanAttributeKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
