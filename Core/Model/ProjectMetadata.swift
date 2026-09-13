//
//  Metadata.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

/// Metadata values captured by the shared project setup screen.
struct ProjectMetadataValues: Hashable, Sendable {
    private var valuesByFieldID: [String: String]

    init(_ valuesByFieldID: [String: String] = [:]) {
        self.valuesByFieldID = valuesByFieldID
    }

    func value(for fieldID: String) -> String {
        valuesByFieldID[fieldID] ?? ""
    }

    /// Returns the captured values keyed by module-owned field identifiers.
    func dictionary() -> [String: String] {
        valuesByFieldID
    }

    mutating func setValue(_ value: String, for fieldID: String) {
        valuesByFieldID[fieldID] = value
    }
}

/// Generic metadata field requested by a feature module during setup.
struct ProjectMetadataField: Hashable, Sendable {
    let id: String
    let title: String
    let isRequired: Bool
    let valueType: ProjectMetadataValueType
    let csvAliases: [String]

    init(
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
enum ProjectMetadataValueType: Hashable, Sendable {
    case string
    case number
    case date
}
