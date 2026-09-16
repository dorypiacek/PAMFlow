import Foundation

public enum ProjectFileNames {
    public nonisolated static let sourceDirectory = "source"
    public nonisolated static let workDirectory = "work"

    public nonisolated static let scanSummary = "recording_summary.json"
}

public enum GeneratedProjectArtifacts {
    public nonisolated static let folderNames: Set<String> = [
        ProjectFileNames.workDirectory,
        ProjectFileNames.sourceDirectory
    ]
}

public enum ProjectScanStatus {
    public nonisolated static let pending = "pending"
    public nonisolated static let unavailable = "unavailable"
}

public enum ProjectQuality {
    public nonisolated static let ok = "OK"
    public nonisolated static let check = "CHECK"
    public nonisolated static let readError = "READ_ERROR"
}
