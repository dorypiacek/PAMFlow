//
//  Metadata.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

/// Metadata values captured by the shared project setup screen.
public struct ProjectMetadataValues: Hashable, Sendable {
    private var valuesByFieldID: [String: String]

    public init(_ valuesByFieldID: [String: String] = [:]) {
        self.valuesByFieldID = valuesByFieldID
    }

    public func value(for fieldID: String) -> String {
        valuesByFieldID[fieldID] ?? ""
    }

    /// Returns the captured values keyed by module-owned field identifiers.
    public func dictionary() -> [String: String] {
        valuesByFieldID
    }

    public mutating func setValue(_ value: String, for fieldID: String) {
        valuesByFieldID[fieldID] = value
    }
}

/// Generic metadata field requested by a feature module during setup.
public struct ProjectMetadataField: Hashable, Sendable {
    public let id: String
    public let title: String
    public let isRequired: Bool
    public let valueType: ProjectMetadataValueType
    public let csvAliases: [String]

    public init(
        id: String,
        title: String,
        isRequired: Bool,
        valueType: ProjectMetadataValueType = .string,
        csvAliases: [String] = []
    ) {
        self.id = id
        self.title = title
        self.isRequired = isRequired
        self.valueType = valueType
        self.csvAliases = csvAliases
    }
}

/// Value type used by the shared project metadata editor.
public enum ProjectMetadataValueType: Hashable, Sendable {
    case string
    case number
    case date
}
