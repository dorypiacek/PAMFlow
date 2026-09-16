//
//  PAMStrings.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation
import UI
import Core

/// User-facing copy owned by the PAM module.
enum PAMStrings {
    enum Preview {
        static let amplitudeAxis = "Amplitude"
        static let frequencyAxis = "Frequency (Hz)"
        static let loading = "Loading preview"
        static let pauseHelp = "Pause"
        static let playHelp = "Play"
        static let timeAxis = "Time (s)"
        static let unavailable = "Preview is unavailable for this file."
    }

    enum Module {
        nonisolated static let title = "PAM Audio"
        nonisolated static let subtitle = "WAV recordings for PAMGuard-based acoustic review."
        nonisolated static let folderName = "Audio"
    }

    enum ProjectSetup {
        static let metadataUploadMessage = "Upload PAM deployment metadata to prefill the required fields."
        static let opcode = "OpCode"
        static let dateDeployed = "Date Deployed"
        static let dateRetrieved = "Date Retrieved"
        static let location = "Location"
        static let depth = "Depth"
        static let bottomType = "Bottom Type"
    }

    enum ScanWarnings {
        static let noAudioFilesFound = "No WAV files were found in the selected folder."
        static let unreadableFilesFound = "Some audio files could not be read."
        static let multipleSampleRatesFound = "Multiple sample rates were detected."
        static let clippedFilesFound = "Some audio files may be clipped."
        static let nearlyEmptyFilesFound = "Some audio files are nearly empty."
        static let largeBatch = "This batch is large and may take a while."
    }

    enum Overview {
        static let readyForPamguard = "Ready for PAMGuard"
        static let goToPamguardSetup = "Go to PAMGuard Setup"
        static let preparePamguardHelp = "Prepare PAMGuard files"
        static let audioDetectionSubtitle = "Review the PAMGuard detection decisions before creating the export."
        static let audioDetectionTitle = "Audio Detection Overview"
        static let bitDepths = "Bit depths found"
        static let sampleRates = "Sample rates found"
    }

    enum ExportPackage {
        static let sourceRecordingNotFound = "Source recording not found"
        static let noGroupedDetectionEvents = "No grouped detection events"
        static let unprocessedStatus = "unprocessed"
        static let processedStatus = "processed"
        static let timeAxis = "Time (s)"
        static let frequencyAxis = "Frequency (Hz)"
        static let spectrogramView = "Spectrogram 1"
        static let fallbackSampleName = "sample"

        static let sampleCSVHeader = [
            "sampleId", "opcode", "recordingFile", "dateDeployed", "dateRetrieved", "location", "depth", "bottomType", "sampleRateHz", "channels", "durationSeconds", "processedBy", "processingStatus", "originalDetectionCount", "confirmedDetectionCount", "exclusionReason"
        ]
        static let eventCSVHeader = [
            "eventId", "sampleId", "opcode", "recordingFile", "channel", "startDateTimeUTC", "endDateTimeUTC", "startOffsetSeconds", "endOffsetSeconds", "durationSeconds", "detectorType", "detectionCount", "minFrequencyHz", "maxFrequencyHz", "processedBy", "reviewStatus", "eventValidity", "reviewer", "notes"
        ]
        static let ravenHeader = [
            "Selection", "View", "Channel", "Begin Time (s)", "End Time (s)", "Low Freq (Hz)", "High Freq (Hz)", "Begin File", "Event ID", "Detector", "Review Status"
        ]
    }

    enum DetectionProgress {
        nonisolated static let readingBinary = "Reading PAMGuard binary detections..."
        nonisolated static let readingDatabaseFallback = "Reading PAMGuard database fallback..."
        nonisolated static let groupingEvents = "Grouping PAMGuard detections into events..."
        nonisolated static let preparingEventFormat = "Preparing event %d/%d"
        nonisolated static let eventsReady = "PAMGuard events are ready for review."
        nonisolated static let decodingBinaryFileFormat = "Decoding binary file %d/%d"
    }

    enum PreparationError {
        nonisolated static let missingProjectFolder = "Project folder could not be opened."
        nonisolated static let missingInputFolder = "Input folder could not be opened."
        nonisolated static let missingTemplate = "The PAMGuard template is missing from the app bundle."
        nonisolated static let noAuditedInputFiles = "No valid or unsure audio files were found in the audit."
        nonisolated static let inputSymlinkFailedFormat = "The PAMGuard input links could not be created: %@"
        nonisolated static let databaseCreationFailedFormat = "The PAMGuard database could not be created: %@"
        nonisolated static let sqliteSymbolsMissing = "SQLite symbols could not be loaded."
        nonisolated static let sqliteOpenFailedFormat = "SQLite open failed with code %d."
        nonisolated static let sqliteInitializationFailedFormat = "SQLite initialization failed with code %d."
    }

    enum DetectionError {
        nonisolated static let missingProjectFolder = "Could not open the project folder."
        nonisolated static let missingInputFolder = "Could not open the input folder."
        nonisolated static let missingDatabase = "No PAMGuard SQLite database was found in the pamguard/db folder."
        nonisolated static let missingBinaryFolder = "No PAMGuard binary folder was found at pamguard/binary."
        nonisolated static let sqliteOpenFailedFormat = "The PAMGuard SQLite database could not be opened: %@"
        nonisolated static let noDetectionsFound = "No PAMGuard detections were found in the binary or database outputs."
    }

    enum Setup {
        static let title = "PAMGuard Setup"
        static let subtitle = "Prepare the PAMGuard template and audited audio inputs."
        static let backButton = "Back to Manual Audit Overview"
        static let question = "What would you like to detect?"
        static let selectDetectionTarget = "Select detection target"
        static let pygmyKillerWhales = "Pygmy killer whales"
        static let generalOdontocetes = "General odontocetes"
        static let preparing = "Preparing PAMGuard files..."
        static let prepared = "PAMGuard template is ready."
        static let showInFinder = "Show in Finder"
        static let instructions = "Open PAMGuard in Normal mode and select the generated template."
        static let continueButton = "Continue"
        static let selectedInputCountFormat = "%d audited audio files linked"
        static let waitingTitle = "Waiting for PAMGuard detections"
        static let waitingSubtitle = "Run the generated template in PAMGuard, then confirm when detections are finished."
        static let confirmRunFinished = "PAMGuard run is finished"
        static let helpButton = "PAMGuard help"
        static let helpTitle = "Run PAMGuard"
        static let helpDownloadStep = "Download PAMGuard for macOS. Apple Silicon is required."
        static let helpDownloadLink = "PAMGuard V2.02.18 release page"
        static let helpStep1 = "Open PAMGuard and select Normal mode."
        static let helpStep2 = "Open the generated pamguard folder and select the .psfx as the template."
        static let helpStep3 = "In PAMGuard, choose File -> Database -> Database Selection, then select the .sqlite file from the db folder."
        static let helpStep4 = "Choose File -> Binary Store -> Storage options, then select the binary folder."
        static let helpStep5 = "Choose File -> Show Data Model, right-click Sound Acquisition, select Settings, and choose the input folder."
        static let helpStep6 = "Close the data model and click Play, the red circle button."
        static let helpStep7 = "Wait for PAMGuard to finish, then return to PAMFlow."
    }

    enum Processing {
        static let title = "Processing PAMGuard Detections"
        static let subtitle = "Importing the PAMGuard run and preparing detection review."
        static let starting = "Starting PAMGuard detection import..."
        static let failed = "PAMGuard detection import failed."
        static let retry = "Retry Import"
    }

    enum Completion {
        static let title = "Project Complete"
        static let subtitle = "Export the PAMGuard detection package or return to the project library."
        static let exportPackage = "Export PAMGuard Package"
        static let complete = "Complete"
        static let backToProjects = "Back to Projects"
        static let projectOverview = "Project Overview"
        static let project = "Project"
        static let processedBy = "Processed By"
        static let reviewedFiles = "Reviewed Files"
        static let validDecisions = "Valid Decisions"
        static let invalidDecisions = "Invalid Decisions"
        static let unsureDecisions = "Unsure Decisions"
        static let exportSuccessFormat = "Exported %@"
    }
}
