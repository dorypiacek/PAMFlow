//
//  ExportField.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

/// Generic export field declaration for the shared CSV exporter.
struct CSVExportFieldDescriptor: Hashable, Sendable {
    let id: String
    let title: String
    let isDefault: Bool

    init(id: String, title: String, isDefault: Bool) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}
