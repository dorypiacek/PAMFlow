import Foundation

extension WorkflowModule {
    nonisolated var projectNamePrefix: String {
        switch self {
        case .pamAudio:
            "PAM"
        case .bruvVideo:
            "BRUV"
        case .ruvImages:
            "RUV"
        }
    }

    nonisolated var supportedFileExtensions: Set<String> {
        switch self {
        case .pamAudio:
            MediaFileExtensions.wavAudio
        case .bruvVideo:
            MediaFileExtensions.video
        case .ruvImages:
            MediaFileExtensions.image
        }
    }

    var selectionIconName: String {
        switch self {
        case .pamAudio:
            Icons.audio
        case .bruvVideo:
            Icons.video
        case .ruvImages:
            Icons.image
        }
    }

    var selectionTitle: String {
        switch self {
        case .pamAudio:
            Strings.DataTypeSelection.pamAudioTitle
        case .bruvVideo:
            Strings.DataTypeSelection.bruvVideoTitle
        case .ruvImages:
            Strings.DataTypeSelection.ruvImageTitle
        }
    }

    var selectionSubtitle: String {
        switch self {
        case .pamAudio:
            Strings.DataTypeSelection.pamAudioSubtitle
        case .bruvVideo:
            Strings.DataTypeSelection.bruvVideoSubtitle
        case .ruvImages:
            Strings.DataTypeSelection.ruvImageSubtitle
        }
    }
}
