import Foundation

enum ProjectFileNames {
    nonisolated static let sourceDirectory = "source"
    nonisolated static let workDirectory = "work"

    nonisolated static let scanSummary = "recording_summary.json"
}

enum MediaFileExtensions {
    nonisolated static let wavAudio: Set<String> = ["wav", "wave"]
    nonisolated static let previewAudio: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "mp3", "m4a", "caf"]
    nonisolated static let video: Set<String> = ["mp4", "mov", "m4v", "avi"]
    nonisolated static let image: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"]
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
    nonisolated static let pamguard = "pamguard"
}

enum ProjectQuality {
    nonisolated static let ok = "OK"
    nonisolated static let check = "CHECK"
    nonisolated static let readError = "READ_ERROR"
}
