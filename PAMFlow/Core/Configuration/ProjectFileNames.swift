import Foundation

enum ProjectFileNames {
    nonisolated static let sourceDirectory = "source"
    nonisolated static let workDirectory = "work"
    nonisolated static let detectionsDirectory = "detections"
    nonisolated static let pamguardDirectory = "pamguard"
    nonisolated static let pamguardDatabaseDirectory = "db"
    nonisolated static let pamguardBinaryDirectory = "binary"
    nonisolated static let pamguardDetectionPreviewDirectory = "pamguard_detection_previews"
    nonisolated static let sharkTrackInternalDirectory = "sharktrack_internal"

    nonisolated static let scanSummary = "recording_summary.json"
    nonisolated static let sharkTrackManifest = "sharktrack_manifest.json"
}

enum MediaFileExtensions {
    nonisolated static let wavAudio: Set<String> = ["wav", "wave"]
    nonisolated static let previewAudio: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "mp3", "m4a", "caf"]
    nonisolated static let video: Set<String> = ["mp4", "mov", "m4v", "avi"]
    nonisolated static let image: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"]
    nonisolated static let sharkTrackImage: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff"]
    nonisolated static let pamguardDatabase: Set<String> = ["sqlite", "sqlite3", "db"]
    nonisolated static let pamguardBinary: Set<String> = ["pgdf", "pgnf", "pgdx"]
}

enum GeneratedProjectArtifacts {
    nonisolated static let folderNames: Set<String> = [
        ProjectFileNames.detectionsDirectory,
        ProjectFileNames.workDirectory,
        ProjectFileNames.pamguardDirectory,
        ProjectFileNames.sourceDirectory
    ]
}

enum ProjectScanStatus {
    nonisolated static let pamguard = "pamguard"
    nonisolated static let pending = "pending"
    nonisolated static let unavailable = "unavailable"
}

enum ProjectQuality {
    nonisolated static let ok = "OK"
    nonisolated static let check = "CHECK"
    nonisolated static let readError = "READ_ERROR"
}

enum PAMGuardPreview {
    nonisolated static let filePrefix = "event"
    nonisolated static let fileExtension = "png"
    nonisolated static let relativeEventDirectory = "pamguard/events"
    nonisolated static let fallbackTitle = "PAMGuard event"
    nonisolated static let eventQualityFlag = "Event"
    nonisolated static let unknownTime = "Unknown"
}
