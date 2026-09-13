import Foundation

enum ProjectFileNames {
    nonisolated static let sourceDirectory = "source"
    nonisolated static let workDirectory = "work"

    nonisolated static let scanSummary = "recording_summary.json"
}

enum GeneratedProjectArtifacts {
    nonisolated static let folderNames: Set<String> = [
        ProjectFileNames.workDirectory,
        ProjectFileNames.sourceDirectory
    ]
}

enum ProjectScanStatus {
    nonisolated static let pending = "pending"
    nonisolated static let unavailable = "unavailable"
}

enum ProjectQuality {
    nonisolated static let ok = "OK"
    nonisolated static let check = "CHECK"
    nonisolated static let readError = "READ_ERROR"
}
