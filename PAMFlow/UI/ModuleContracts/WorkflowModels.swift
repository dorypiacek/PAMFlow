//
//  WorkflowModels.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation

/// Configuration consumed by the shared project setup screen.
struct ProjectSetupConfiguration: Hashable, Sendable {
    let module: ModuleDetails
    let requiredMetadataFields: [ProjectMetadataField]

    init(module: ModuleDetails, requiredMetadataFields: [ProjectMetadataField]) {
        self.module = module
        self.requiredMetadataFields = requiredMetadataFields
    }
}

/// Generic metadata field requested by a feature module during setup.
struct ProjectMetadataField: Hashable, Sendable {
    let id: String
    let title: String
    let isRequired: Bool

    init(id: String, title: String, isRequired: Bool) {
        self.id = id
        self.title = title
        self.isRequired = isRequired
    }
}

/// Configuration consumed by the shared audit shell.
struct ManualAuditConfiguration: Hashable, Sendable {
    let title: String
    let emptyStateTitle: String
    let decisionOptions: [AuditDecisionOption]

    init(title: String, emptyStateTitle: String, decisionOptions: [AuditDecisionOption]) {
        self.title = title
        self.emptyStateTitle = emptyStateTitle
        self.decisionOptions = decisionOptions
    }
}

/// Generic audit decision exposed by a module.
struct AuditDecisionOption: Hashable, Sendable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

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
