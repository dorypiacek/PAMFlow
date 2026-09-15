//
//  ExportField.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

/// Generic export field declaration for the shared CSV exporter.
public struct CSVExportFieldDescriptor: Hashable, Sendable {
    public let id: String
    public let title: String
    public let isDefault: Bool

    public init(id: String, title: String, isDefault: Bool) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}
