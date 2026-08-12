// 
//  PAMDetectionPackageExporter.swift
//  PAMFlow
// 
//  Created by Dory on 29/07/2026.
// 

import AppKit
import AVFoundation
import Foundation

private enum PAMExportFileNames {
    static let samplesCSV = "samples.csv"
    static let detectionEventsCSV = "detection_events.csv"
    static let samplesDirectory = "samples"
    static let spectrogramsDirectory = "spectrograms"
    static let ravenSelectionExtension = "selections.txt"
    static let spectrogramImageExtension = "png"
}

private enum PAMExportSeparators {
    static let comma = ","
    static let tab = "\t"
    static let newline = "\n"
    static let carriageReturn = "\r"
    static let fieldList = "; "
}

private enum PAMExportMetadataKey {
    static let file = "File"
    static let startTime = "Start time"
    static let endTime = "End time"
    static let evidenceTypes = "Evidence types"
    static let clickCount = "Click count"
    static let clickBoutCount = "Click bout count"
    static let clickTrainCount = "Click train count"
    static let whistleCount = "Whistle count"
    static let lowFrequency = "Low frequency"
    static let highFrequency = "High frequency"
    static let secondsSuffix = " s"
}

private enum PAMExportMetadataField {
    static let dateDeployed = "dateDeployed"
    static let dateRetrieved = "dateRetrieved"
    static let location = "location"
    static let depth = "depth"
    static let bottomType = "bottomType"
    static let sampleRateHz = "sampleRateHz"
    static let channels = "channels"
    static let durationSeconds = "durationSeconds"
}

private enum ProjectExportFieldID {
    static let eventID = "event_id"
    static let fileID = "file_id"
    static let eventStartSeconds = "event_start_seconds"
    static let eventEndSeconds = "event_end_seconds"
    static let score = "score"
    static let evidenceTypes = "evidence_types"
    static let detectors = "detectors"
    static let clickCount = "click_count"
    static let clickBoutCount = "click_bout_count"
    static let clickTrainCount = "click_train_count"
    static let whistleCount = "whistle_count"
    static let qualityFlags = "quality_flags"
    static let reviewStatus = "review_status"
    static let detectionID = "detection_id"
    static let opcode = "opcode"
    static let deploymentDate = "deployment_date"
    static let retrievalDate = "retrieval_date"
    static let location = "location"
    static let depth = "depth"
    static let bottomType = "bottom_type"
    static let waterTemperature = "water_temperature"
    static let fileName = "file_name"
    static let relativePath = "relative_path"
    static let sourceMedia = "source_media"
    static let processedBy = "processed_by"
    static let decision = "decision"
    static let reason = "reason"
    static let speciesFamily = "species_family"
    static let speciesGenus = "species_genus"
    static let speciesName = "species_name"
    static let speciesFullName = "species_full_name"
    static let durationSeconds = "duration_seconds"
    static let clipStartSeconds = "clip_start_seconds"
    static let clipDurationSeconds = "clip_duration_seconds"
    static let sampleRateHz = "sample_rate_hz"
    static let channels = "channels"
    static let bitDepth = "bit_depth"
    static let peakDBFS = "peak_dbfs"
    static let rmsDBFS = "rms_dbfs"
    static let detector = "detector"
    static let frameNumber = "frame_number"
    static let trackID = "track_id"
    static let maxN = "max_n"
    static let confidence = "confidence"
    static let frameCount = "frame_count"
    static let frameRate = "frame_rate"
    static let width = "width"
    static let height = "height"
    static let format = "format"
    static let sizeBytes = "size_bytes"
    static let qualityFlag = "quality_flag"
    static let qualityReasons = "quality_reasons"
}

/// Builds the PAM workflow export package, including sample/event CSV files, per-sample Raven selection tables, and high-resolution event spectrograms.
struct ProjectExportReport {
    let project: Project
    let summary: ProjectScanSummary
    let decisions: [ManualAuditDecision]
    let fields: [ProjectExportField]
    let separator: String
    let processedBy: String

    var string: String {
        let decisionsByPath = Dictionary(uniqueKeysWithValues: decisions.map { ($0.fileRelativePath, $0) })
        let header = fields.map(\.title).map(escape).joined(separator: separator)
        let rows = summary.files.map { file in
            let decision = decisionsByPath[file.relativePath]
            return fields
                .map { field in
                    if field.id == ProjectExportField.processedByFieldID {
                        escape(processedBy)
                    } else {
                        escape(field.value(project, file, decision))
                    }
                }
                .joined(separator: separator)
        }
        return ([header] + rows).joined(separator: PAMExportSeparators.newline) + PAMExportSeparators.newline
    }

    private func escape(_ value: String) -> String {
        if separator == PAMExportSeparators.comma {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return value.contains(PAMExportSeparators.comma) || value.contains(PAMExportSeparators.newline) || value.contains("\"") ? "\"\(escaped)\"" : escaped
        }

        return value
            .replacingOccurrences(of: PAMExportSeparators.tab, with: " ")
            .replacingOccurrences(of: PAMExportSeparators.newline, with: " ")
    }
}

struct PAMDetectionPackageExporter {
    let project: Project
    let summary: ProjectScanSummary
    let decisions: [ManualAuditDecision]
    let processedBy: String

    private var decisionsByPath: [String: ManualAuditDecision] {
        Dictionary(uniqueKeysWithValues: decisions.map { ($0.fileRelativePath, $0) })
    }

    func writePackage(to packageURL: URL) throws {
        let inputFolderURL = project.inputFolderURL
        let accessedInput = inputFolderURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessedInput {
                inputFolderURL?.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: packageURL, withIntermediateDirectories: true)

        let samples = sampleRows()
        let events = eventRows(samples: samples)
        try csv(rows: samples.map(\.csvValues), header: PAMSampleRow.csvHeader)
            .write(to: packageURL.appendingPathComponent(PAMExportFileNames.samplesCSV), atomically: true, encoding: .utf8)
        try csv(rows: events.map(\.csvValues), header: PAMEventRow.csvHeader)
            .write(to: packageURL.appendingPathComponent(PAMExportFileNames.detectionEventsCSV), atomically: true, encoding: .utf8)
        try writeSampleFolders(samples: samples, events: events, packageURL: packageURL)
    }

    private func sampleRows() -> [PAMSampleRow] {
        let sourceFiles = audioSourceFiles()
        let eventsBySample = Dictionary(grouping: summary.files, by: sampleID(for:))
        let sampleIDs = Set(sourceFiles.map(\.sampleID)).union(eventsBySample.keys)

        return sampleIDs.sorted().map { sampleID in
            let source = sourceFiles.first { $0.sampleID == sampleID }
            let eventFiles = eventsBySample[sampleID] ?? []
            let decisions = eventFiles.compactMap { decisionsByPath[$0.relativePath] }
            let confirmedCount = decisions.filter { $0.decision == .valid }.count
            let originalCount = eventFiles.reduce(0) { $0 + detectionCount(for: $1) }
            let exclusionReason: String
            if source == nil {
                exclusionReason = Strings.PAMDetectionPackage.sourceRecordingNotFound
            } else if eventFiles.isEmpty {
                exclusionReason = Strings.PAMDetectionPackage.noGroupedDetectionEvents
            } else {
                exclusionReason = decisions
                    .filter { $0.decision != .valid && !$0.notes.isEmpty }
                    .map(\.notes)
                    .uniqueStrings()
                    .joined(separator: PAMExportSeparators.fieldList)
            }

            return PAMSampleRow(
                sampleID: sampleID,
                opcode: project.metadataOpcode ?? "",
                recordingFile: source?.url.lastPathComponent ?? eventFiles.first?.sourceVideo ?? sampleID,
                metadata: sampleMetadata(source: source),
                processedBy: processedBy,
                processingStatus: source == nil ? Strings.PAMDetectionPackage.unprocessedStatus : Strings.PAMDetectionPackage.processedStatus,
                originalDetectionCount: originalCount,
                confirmedDetectionCount: confirmedCount,
                exclusionReason: exclusionReason,
                sourceURL: source?.url,
                sampleRateHz: source?.sampleRateHz ?? eventFiles.first?.sampleRateHz.map(Double.init)
            )
        }
    }

    private func eventRows(samples: [PAMSampleRow]) -> [PAMEventRow] {
        let sampleByID = Dictionary(uniqueKeysWithValues: samples.map { ($0.sampleID, $0) })
        return summary.files.sorted { lhs, rhs in
            let leftSample = sampleID(for: lhs)
            let rightSample = sampleID(for: rhs)
            if leftSample == rightSample {
                return startOffset(for: lhs) < startOffset(for: rhs)
            }
            return leftSample.localizedStandardCompare(rightSample) == .orderedAscending
        }
        .map { file in
            let decision = decisionsByPath[file.relativePath]
            let sampleID = sampleID(for: file)
            let sample = sampleByID[sampleID]
            let startOffset = startOffset(for: file)
            let endOffset = endOffset(for: file)
            let startDate = dateTimeUTC(sample: sample, offset: startOffset)
            let endDate = dateTimeUTC(sample: sample, offset: endOffset)
            return PAMEventRow(
                eventID: eventID(for: file),
                sampleID: sampleID,
                opcode: project.metadataOpcode ?? "",
                recordingFile: sample?.recordingFile ?? file.sourceVideo ?? "",
                channel: channel(for: file),
                startDateTimeUTC: startDate,
                endDateTimeUTC: endDate,
                startOffsetSeconds: startOffset,
                endOffsetSeconds: endOffset,
                durationSeconds: max(0, endOffset - startOffset),
                detectorType: detectorType(for: file),
                detectionCount: detectionCount(for: file),
                minFrequencyHz: frequencyLowerBound(for: file, sampleRateHz: sample?.sampleRateHz),
                maxFrequencyHz: frequencyUpperBound(for: file, sampleRateHz: sample?.sampleRateHz),
                processedBy: processedBy,
                reviewStatus: decision == nil ? Strings.Common.unreviewed : Strings.Common.reviewed,
                eventValidity: decision?.decision.title ?? "",
                reviewer: decision == nil ? "" : processedBy,
                notes: decision?.notes ?? "",
                sourceFile: file
            )
        }
    }

    private func writeSampleFolders(samples: [PAMSampleRow], events: [PAMEventRow], packageURL: URL) throws {
        let samplesURL = packageURL.appendingPathComponent(PAMExportFileNames.samplesDirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: samplesURL, withIntermediateDirectories: true)
        let eventsBySample = Dictionary(grouping: events, by: \.sampleID)

        for sample in samples where eventsBySample[sample.sampleID]?.isEmpty == false {
            let sampleFolder = samplesURL.appendingPathComponent(sanitizePathComponent(sample.sampleID), isDirectory: true)
            let spectrogramFolder = sampleFolder.appendingPathComponent(PAMExportFileNames.spectrogramsDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: spectrogramFolder, withIntermediateDirectories: true)

            if let sourceURL = sample.sourceURL {
                let destination = sampleFolder.appendingPathComponent(sourceURL.lastPathComponent)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                }
            }

            let sampleEvents = eventsBySample[sample.sampleID] ?? []
            try ravenSelectionTable(events: sampleEvents, sample: sample)
                .write(
                    to: sampleFolder.appendingPathComponent("\(sanitizePathComponent(sample.sampleID)).\(PAMExportFileNames.ravenSelectionExtension)"),
                    atomically: true,
                    encoding: .utf8
                )

            for event in sampleEvents {
                let imageName = "\(sanitizePathComponent(event.eventID))_\(decimal(event.startOffsetSeconds))-\(decimal(event.endOffsetSeconds)).\(PAMExportFileNames.spectrogramImageExtension)"
                try renderSpectrogram(
                    event: event,
                    sample: sample,
                    to: spectrogramFolder.appendingPathComponent(imageName)
                )
            }
        }
    }

    private func renderSpectrogram(event: PAMEventRow, sample: PAMSampleRow, to url: URL) throws {
        guard let sourceURL = sample.sourceURL else { return }
        let preview = try AudioPreviewService().loadPreview(
            from: sourceURL,
            clipStartSeconds: event.startOffsetSeconds,
            clipDurationSeconds: max(1, event.durationSeconds)
        )
        let size = CGSize(width: 1800, height: 1100)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()

        let title = "\(event.eventID) | \(event.detectorType)"
        let subtitle = "\(decimal(event.startOffsetSeconds))-\(decimal(event.endOffsetSeconds)) s | \(frequencyLabel(low: event.minFrequencyHz, high: event.maxFrequencyHz))"
        title.draw(at: CGPoint(x: 72, y: 1028), withAttributes: [
            .font: NSFont.boldSystemFont(ofSize: 30),
            .foregroundColor: NSColor.labelColor
        ])
        subtitle.draw(at: CGPoint(x: 72, y: 984), withAttributes: [
            .font: NSFont.systemFont(ofSize: 22),
            .foregroundColor: NSColor.secondaryLabelColor
        ])

        drawSpectrogram(preview.spectrogramBins, sampleRateHz: preview.sampleRateHz, rect: CGRect(x: 72, y: 92, width: 1656, height: 840))
        image.unlockFocus()

        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [.compressionFactor: 0.9]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }

    private func drawSpectrogram(_ bins: [[Float]], sampleRateHz: Double, rect: CGRect) {
        NSColor(calibratedRed: 0.02, green: 0.01, blue: 0.06, alpha: 1).setFill()
        NSBezierPath(rect: rect).fill()
        guard let firstColumn = bins.first, !firstColumn.isEmpty else { return }

        let maxFrequency = min(max(sampleRateHz / 2, 1), 50_000)
        let columns = min(bins.count, Int(rect.width))
        let rows = min(firstColumn.count, Int(rect.height))
        let cellWidth = rect.width / CGFloat(columns)
        let cellHeight = rect.height / CGFloat(rows)

        for column in 0..<columns {
            let sourceColumn = min(bins.count - 1, column * bins.count / columns)
            for row in 0..<rows {
                let sourceRow = min(firstColumn.count - 1, row * firstColumn.count / rows)
                spectrogramColor(Double(bins[sourceColumn][sourceRow])).setFill()
                NSBezierPath(rect: NSRect(
                    x: rect.minX + CGFloat(column) * cellWidth,
                    y: rect.minY + CGFloat(row) * cellHeight,
                    width: cellWidth + 0.5,
                    height: cellHeight + 0.5
                )).fill()
            }
        }

        NSColor.black.setStroke()
        NSBezierPath(rect: rect).stroke()
        let axisAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        Strings.PAMDetectionPackage.timeAxis.draw(at: CGPoint(x: rect.midX - 34, y: 42), withAttributes: axisAttributes)
        Strings.PAMDetectionPackage.frequencyAxis.draw(at: CGPoint(x: rect.minX, y: rect.maxY + 18), withAttributes: axisAttributes)
        for tick in stride(from: 0.0, through: maxFrequency, by: maxFrequency <= 50_000 ? 10_000 : 25_000) {
            let y = rect.minY + rect.height * CGFloat(tick / maxFrequency)
            "\(Int(tick))".draw(at: CGPoint(x: 12, y: y - 9), withAttributes: axisAttributes)
        }
    }

    private func spectrogramColor(_ value: Double) -> NSColor {
        let stops: [(Double, Double, Double)] = [
            (0.02, 0.01, 0.08),
            (0.11, 0.04, 0.28),
            (0.39, 0.08, 0.51),
            (0.86, 0.24, 0.45),
            (1.00, 0.55, 0.22),
            (1.00, 0.92, 0.60)
        ]
        let clamped = pow(min(1, max(0, value)), 0.55)
        let scaled = clamped * Double(stops.count - 1)
        let lower = min(Int(scaled), stops.count - 2)
        let fraction = scaled - Double(lower)
        let a = stops[lower]
        let b = stops[lower + 1]
        return NSColor(
            calibratedRed: a.0 + (b.0 - a.0) * fraction,
            green: a.1 + (b.1 - a.1) * fraction,
            blue: a.2 + (b.2 - a.2) * fraction,
            alpha: 1
        )
    }

    private func ravenSelectionTable(events: [PAMEventRow], sample: PAMSampleRow) -> String {
        let header = Strings.PAMDetectionPackage.ravenHeader
        let rows = events.enumerated().map { index, event in
            [
                "\(index + 1)",
                Strings.PAMDetectionPackage.spectrogramView,
                event.channel,
                decimal(event.startOffsetSeconds),
                decimal(event.endOffsetSeconds),
                decimal(event.minFrequencyHz),
                decimal(event.maxFrequencyHz),
                sample.recordingFile,
                event.eventID,
                event.detectorType,
                event.reviewStatus
            ].map(sanitizeCell).joined(separator: PAMExportSeparators.tab)
        }
        return ([header.joined(separator: PAMExportSeparators.tab)] + rows)
            .joined(separator: PAMExportSeparators.newline) + PAMExportSeparators.newline
    }

    private func csv(rows: [[String]], header: [String]) -> String {
        ([header] + rows)
            .map { $0.map(csvEscape).joined(separator: PAMExportSeparators.comma) }
            .joined(separator: PAMExportSeparators.newline) + PAMExportSeparators.newline
    }

    private func audioSourceFiles() -> [PAMAudioSource] {
        guard let inputFolderURL = project.inputFolderURL else { return [] }
        let urls = (FileManager.default.enumerator(at: inputFolderURL, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL }
            .filter { url in
                ((try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true) &&
                    MediaFileExtensions.wavAudio.contains(url.pathExtension.lowercased())
            } ?? [])
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return urls.map { url in
            let file = try? AVAudioFile(forReading: url)
            return PAMAudioSource(
                sampleID: url.deletingPathExtension().lastPathComponent,
                url: url,
                durationSeconds: file.map { Double($0.length) / $0.processingFormat.sampleRate },
                sampleRateHz: file?.processingFormat.sampleRate,
                channels: file.map { Int($0.processingFormat.channelCount) }
            )
        }
    }

    private func sampleMetadata(source: PAMAudioSource?) -> [String: String] {
        [
            PAMExportMetadataField.dateDeployed: project.metadataDate ?? "",
            PAMExportMetadataField.dateRetrieved: project.metadataDateRetrieved ?? "",
            PAMExportMetadataField.location: project.metadataLocation ?? "",
            PAMExportMetadataField.depth: project.metadataDepth ?? "",
            PAMExportMetadataField.bottomType: project.metadataBottomType ?? "",
            PAMExportMetadataField.sampleRateHz: source?.sampleRateHz.map { decimal($0) } ?? "",
            PAMExportMetadataField.channels: source?.channels.map(String.init) ?? "",
            PAMExportMetadataField.durationSeconds: source?.durationSeconds.map { decimal($0) } ?? ""
        ]
    }

    private func sampleID(for file: ProjectScanFile) -> String {
        let source = file.sourceVideo ?? metadataValue(file, key: PAMExportMetadataKey.file)
        return URL(fileURLWithPath: source.isEmpty ? file.relativePath : source).deletingPathExtension().lastPathComponent
    }

    private func eventID(for file: ProjectScanFile) -> String {
        file.relativePath
            .replacingOccurrences(of: "pamguard/events/", with: "")
            .replacingOccurrences(of: "pamguard/detections/", with: "")
    }

    private func startOffset(for file: ProjectScanFile) -> Double {
        double(metadataValue(file, key: PAMExportMetadataKey.startTime)) ?? file.clipStartSeconds ?? 0
    }

    private func endOffset(for file: ProjectScanFile) -> Double {
        if let value = double(metadataValue(file, key: PAMExportMetadataKey.endTime)) {
            return value
        }
        return startOffset(for: file) + (file.durationSeconds ?? file.clipDurationSeconds ?? 0)
    }

    private func detectorType(for file: ProjectScanFile) -> String {
        let detectors = metadataValue(file, key: Strings.ExportFields.detectors)
        if !detectors.isEmpty { return detectors }
        return file.format ?? ""
    }

    private func detectionCount(for file: ProjectScanFile) -> Int {
        let counts = [
            int(metadataValue(file, key: PAMExportMetadataKey.clickCount)),
            int(metadataValue(file, key: PAMExportMetadataKey.clickTrainCount)),
            int(metadataValue(file, key: PAMExportMetadataKey.whistleCount))
        ].compactMap { $0 }
        return max(counts.reduce(0, +), 1)
    }

    private func channel(for file: ProjectScanFile) -> String {
        file.channels.map(String.init) ?? "1"
    }

    private func frequencyLowerBound(for file: ProjectScanFile, sampleRateHz: Double?) -> Double {
        double(metadataValue(file, key: PAMExportMetadataKey.lowFrequency)) ?? 0
    }

    private func frequencyUpperBound(for file: ProjectScanFile, sampleRateHz: Double?) -> Double {
        double(metadataValue(file, key: PAMExportMetadataKey.highFrequency)) ?? sampleRateHz.map { $0 / 2 } ?? Double(file.sampleRateHz ?? 0) / 2
    }

    private func dateTimeUTC(sample: PAMSampleRow?, offset: Double) -> String {
        guard let recordingFile = sample?.recordingFile,
              let date = recordingStartDate(from: recordingFile) else { return "" }
        return Self.isoFormatter.string(from: date.addingTimeInterval(offset))
    }

    private func recordingStartDate(from fileName: String) -> Date? {
        let stem = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        for pattern in ["yyyyMMdd_HHmmss", "yyyy-MM-dd_HH-mm-ss", "yyyyMMdd-HHmmss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = pattern
            if let match = stem.range(of: #"(\d{8}[_-]\d{6}|\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2})"#, options: .regularExpression),
               let date = formatter.date(from: String(stem[match])) {
                return date
            }
        }
        return nil
    }

    private func metadataValue(_ file: ProjectScanFile, key: String) -> String {
        let prefix = "\(key):"
        return file.qualityReasons
            .first { $0.lowercased().hasPrefix(prefix.lowercased()) }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }

    private func double(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: PAMExportMetadataKey.secondsSuffix, with: "").trimmed)
    }

    private func int(_ value: String) -> Int? {
        Int(value.trimmed)
    }

    private func decimal(_ value: Double) -> String {
        Self.posixNumberFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private func frequencyLabel(low: Double, high: Double) -> String {
        "\(decimal(low))-\(decimal(high)) Hz"
    }

    private func csvEscape(_ value: String) -> String {
        let sanitized = sanitizeCell(value)
        let escaped = sanitized.replacingOccurrences(of: "\"", with: "\"\"")
        return sanitized.contains(PAMExportSeparators.comma) || sanitized.contains("\"") ? "\"\(escaped)\"" : sanitized
    }

    private func sanitizeCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: PAMExportSeparators.tab, with: " ")
            .replacingOccurrences(of: PAMExportSeparators.newline, with: " ")
            .replacingOccurrences(of: PAMExportSeparators.carriageReturn, with: " ")
    }

    private func sanitizePathComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
            .union(.newlines)
        let sanitized = value.components(separatedBy: invalid).joined(separator: "_")
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Strings.PAMDetectionPackage.fallbackSampleName : sanitized
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let posixNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}

private struct PAMAudioSource {
    let sampleID: String
    let url: URL
    let durationSeconds: Double?
    let sampleRateHz: Double?
    let channels: Int?
}

private struct PAMSampleRow {
    static let csvHeader = Strings.PAMDetectionPackage.sampleCSVHeader

    let sampleID: String
    let opcode: String
    let recordingFile: String
    let metadata: [String: String]
    let processedBy: String
    let processingStatus: String
    let originalDetectionCount: Int
    let confirmedDetectionCount: Int
    let exclusionReason: String
    let sourceURL: URL?
    let sampleRateHz: Double?

    var csvValues: [String] {
        [
            sampleID,
            opcode,
            recordingFile,
            metadata[PAMExportMetadataField.dateDeployed] ?? "",
            metadata[PAMExportMetadataField.dateRetrieved] ?? "",
            metadata[PAMExportMetadataField.location] ?? "",
            metadata[PAMExportMetadataField.depth] ?? "",
            metadata[PAMExportMetadataField.bottomType] ?? "",
            metadata[PAMExportMetadataField.sampleRateHz] ?? "",
            metadata[PAMExportMetadataField.channels] ?? "",
            metadata[PAMExportMetadataField.durationSeconds] ?? "",
            processedBy,
            processingStatus,
            "\(originalDetectionCount)",
            "\(confirmedDetectionCount)",
            exclusionReason
        ]
    }
}

private struct PAMEventRow {
    static let csvHeader = Strings.PAMDetectionPackage.eventCSVHeader

    let eventID: String
    let sampleID: String
    let opcode: String
    let recordingFile: String
    let channel: String
    let startDateTimeUTC: String
    let endDateTimeUTC: String
    let startOffsetSeconds: Double
    let endOffsetSeconds: Double
    let durationSeconds: Double
    let detectorType: String
    let detectionCount: Int
    let minFrequencyHz: Double
    let maxFrequencyHz: Double
    let processedBy: String
    let reviewStatus: String
    let eventValidity: String
    let reviewer: String
    let notes: String
    let sourceFile: ProjectScanFile

    var csvValues: [String] {
        [
            eventID,
            sampleID,
            opcode,
            recordingFile,
            channel,
            startDateTimeUTC,
            endDateTimeUTC,
            String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), startOffsetSeconds),
            String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), endOffsetSeconds),
            String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), durationSeconds),
            detectorType,
            "\(detectionCount)",
            String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), minFrequencyHz),
            String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), maxFrequencyHz),
            processedBy,
            reviewStatus,
            eventValidity,
            reviewer,
            notes
        ]
    }
}

struct ProjectExportField: Identifiable {
    static let processedByFieldID = ProjectExportFieldID.processedBy

    let id: String
    let title: String
    let modules: Set<WorkflowModule>
    let value: (Project, ProjectScanFile, ManualAuditDecision?) -> String

    static func available(for module: WorkflowModule) -> [ProjectExportField] {
        all.filter { $0.modules.contains(module) }
    }

    static func defaults(for module: WorkflowModule) -> [ProjectExportField] {
        let defaultIDs: [String]
        switch module {
        case .pamAudio:
            defaultIDs = [
                ProjectExportFieldID.eventID,
                ProjectExportFieldID.opcode,
                ProjectExportFieldID.deploymentDate,
                ProjectExportFieldID.retrievalDate,
                ProjectExportFieldID.location,
                ProjectExportFieldID.depth,
                ProjectExportFieldID.bottomType,
                ProjectExportFieldID.fileID,
                ProjectExportFieldID.eventStartSeconds,
                ProjectExportFieldID.eventEndSeconds,
                ProjectExportFieldID.score,
                ProjectExportFieldID.evidenceTypes,
                ProjectExportFieldID.sourceMedia,
                ProjectExportFieldID.clipStartSeconds,
                ProjectExportFieldID.clipDurationSeconds,
                ProjectExportFieldID.clickCount,
                ProjectExportFieldID.clickTrainCount,
                ProjectExportFieldID.whistleCount,
                ProjectExportFieldID.decision,
                ProjectExportFieldID.reason,
                ProjectExportFieldID.speciesFullName,
                processedByFieldID
            ]
        case .bruvVideo:
            defaultIDs = [
                ProjectExportFieldID.fileName,
                ProjectExportFieldID.sourceMedia,
                ProjectExportFieldID.opcode,
                ProjectExportFieldID.deploymentDate,
                ProjectExportFieldID.location,
                ProjectExportFieldID.depth,
                ProjectExportFieldID.bottomType,
                ProjectExportFieldID.waterTemperature,
                ProjectExportFieldID.frameNumber,
                ProjectExportFieldID.trackID,
                ProjectExportFieldID.decision,
                ProjectExportFieldID.reason,
                ProjectExportFieldID.speciesFullName,
                ProjectExportFieldID.confidence,
                ProjectExportFieldID.maxN,
                processedByFieldID
            ]
        case .ruvImages:
            defaultIDs = [
                ProjectExportFieldID.fileName,
                ProjectExportFieldID.sourceMedia,
                ProjectExportFieldID.relativePath,
                ProjectExportFieldID.opcode,
                ProjectExportFieldID.deploymentDate,
                ProjectExportFieldID.location,
                ProjectExportFieldID.depth,
                ProjectExportFieldID.bottomType,
                ProjectExportFieldID.waterTemperature,
                ProjectExportFieldID.decision,
                ProjectExportFieldID.reason,
                ProjectExportFieldID.speciesFullName,
                ProjectExportFieldID.maxN,
                ProjectExportFieldID.width,
                ProjectExportFieldID.height,
                ProjectExportFieldID.format,
                processedByFieldID
            ]
        }

        return defaultIDs.compactMap { field(id: $0, module: module) }
    }

    static func includingRequiredDefaults(_ fieldIDs: [String], for module: WorkflowModule) -> [String] {
        var resolvedFieldIDs = fieldIDs
        for requiredID in requiredDefaultFieldIDs(for: module) where !resolvedFieldIDs.contains(requiredID) {
            resolvedFieldIDs.append(requiredID)
        }
        return resolvedFieldIDs
    }

    private static func requiredDefaultFieldIDs(for module: WorkflowModule) -> [String] {
        switch module {
        case .pamAudio:
            [processedByFieldID]
        case .bruvVideo, .ruvImages:
            [ProjectExportFieldID.fileName, ProjectExportFieldID.sourceMedia, processedByFieldID]
        }
    }

    static func field(id: String, module: WorkflowModule) -> ProjectExportField? {
        available(for: module).first { $0.id == id }
    }

    private static let all: [ProjectExportField] = [
        field(ProjectExportFieldID.eventID, Strings.ExportFields.eventID, modules: [.pamAudio]) { file, _ in eventID(file) },
        field(ProjectExportFieldID.fileID, Strings.ExportFields.fileID, modules: [.pamAudio]) { file, _ in file.sourceVideo ?? metadataValue(file, key: PAMExportMetadataKey.file) },
        field(ProjectExportFieldID.eventStartSeconds, Strings.ExportFields.eventStartSeconds, modules: [.pamAudio]) { file, _ in metadataValue(file, key: PAMExportMetadataKey.startTime).replacingOccurrences(of: PAMExportMetadataKey.secondsSuffix, with: "") },
        field(ProjectExportFieldID.eventEndSeconds, Strings.ExportFields.eventEndSeconds, modules: [.pamAudio]) { file, _ in metadataValue(file, key: PAMExportMetadataKey.endTime).replacingOccurrences(of: PAMExportMetadataKey.secondsSuffix, with: "") },
        field(ProjectExportFieldID.score, Strings.ExportFields.score, modules: [.pamAudio]) { file, _ in number(file.sharkTrackConfidence).isEmpty ? metadataValue(file, key: Strings.ExportFields.score) : number(file.sharkTrackConfidence) },
        field(ProjectExportFieldID.evidenceTypes, Strings.ExportFields.evidenceTypes, modules: [.pamAudio]) { file, _ in file.format ?? metadataValue(file, key: PAMExportMetadataKey.evidenceTypes) },
        field(ProjectExportFieldID.detectors, Strings.ExportFields.detectors, modules: [.pamAudio]) { file, _ in metadataValue(file, key: Strings.ExportFields.detectors) },
        field(ProjectExportFieldID.clickCount, Strings.ExportFields.clickCount, modules: [.pamAudio]) { file, _ in metadataValue(file, key: PAMExportMetadataKey.clickCount) },
        field(ProjectExportFieldID.clickBoutCount, Strings.ExportFields.clickBoutCount, modules: [.pamAudio]) { file, _ in metadataValue(file, key: PAMExportMetadataKey.clickBoutCount) },
        field(ProjectExportFieldID.clickTrainCount, Strings.ExportFields.clickTrainCount, modules: [.pamAudio]) { file, _ in metadataValue(file, key: PAMExportMetadataKey.clickTrainCount) },
        field(ProjectExportFieldID.whistleCount, Strings.ExportFields.whistleCount, modules: [.pamAudio]) { file, _ in metadataValue(file, key: PAMExportMetadataKey.whistleCount) },
        field(ProjectExportFieldID.qualityFlags, Strings.ExportFields.qualityFlags, modules: [.pamAudio]) { file, _ in file.qualityFlag == PAMGuardPreview.eventQualityFlag ? "" : file.qualityFlag },
        field(ProjectExportFieldID.reviewStatus, Strings.ExportFields.reviewStatus, modules: [.pamAudio]) { _, decision in decision?.decision.title ?? Strings.Common.unreviewed },
        field(ProjectExportFieldID.detectionID, Strings.ExportFields.detectionID, modules: [.bruvVideo]) { file, _ in
            file.trackID.map(String.init) ?? file.relativePath
        },
        projectField(ProjectExportFieldID.opcode, Strings.ExportFields.opcode, modules: [.pamAudio, .bruvVideo, .ruvImages]) { $0.metadataOpcode ?? "" },
        projectField(ProjectExportFieldID.deploymentDate, Strings.ExportFields.dateDeployed, modules: [.pamAudio, .bruvVideo, .ruvImages]) { $0.metadataDate ?? "" },
        projectField(ProjectExportFieldID.retrievalDate, Strings.ExportFields.dateRetrieved, modules: [.pamAudio]) { $0.metadataDateRetrieved ?? "" },
        projectField(ProjectExportFieldID.location, Strings.ExportFields.location, modules: [.pamAudio, .bruvVideo, .ruvImages]) { $0.metadataLocation ?? "" },
        projectField(ProjectExportFieldID.depth, Strings.ExportFields.depth, modules: [.pamAudio, .bruvVideo, .ruvImages]) { $0.metadataDepth ?? "" },
        projectField(ProjectExportFieldID.bottomType, Strings.ExportFields.bottomType, modules: [.pamAudio, .bruvVideo, .ruvImages]) { $0.metadataBottomType ?? "" },
        projectField(ProjectExportFieldID.waterTemperature, Strings.ExportFields.waterTemperature, modules: [.bruvVideo, .ruvImages]) { $0.metadataWaterTemperature ?? "" },
        field(ProjectExportFieldID.fileName, Strings.ExportFields.fileName, modules: [.pamAudio]) { file, _ in file.fileName },
        field(ProjectExportFieldID.fileName, Strings.ExportFields.detectionFile, modules: [.bruvVideo, .ruvImages]) { file, _ in file.fileName },
        field(ProjectExportFieldID.relativePath, Strings.ExportFields.relativePath, modules: [.pamAudio, .bruvVideo, .ruvImages]) { file, _ in file.relativePath },
        field(ProjectExportFieldID.sourceMedia, Strings.ExportFields.sourceMedia, modules: [.pamAudio, .bruvVideo, .ruvImages]) { file, _ in sourceMediaDisplayName(for: file) },
        projectField(processedByFieldID, Strings.ExportFields.processedBy, modules: [.pamAudio, .bruvVideo, .ruvImages]) { _ in "" },
        field(ProjectExportFieldID.decision, Strings.ExportFields.decision, modules: [.pamAudio, .bruvVideo, .ruvImages]) { _, decision in decision?.decision.title ?? "" },
        field(ProjectExportFieldID.reason, Strings.ExportFields.reason, modules: [.pamAudio, .bruvVideo, .ruvImages]) { _, decision in decision?.notes ?? "" },
        field(ProjectExportFieldID.speciesFamily, Strings.ExportFields.speciesFamily, modules: [.pamAudio, .bruvVideo, .ruvImages]) { _, decision in decision?.speciesFamily ?? "" },
        field(ProjectExportFieldID.speciesGenus, Strings.ExportFields.speciesGenus, modules: [.pamAudio, .bruvVideo, .ruvImages]) { _, decision in decision?.speciesGenus ?? "" },
        field(ProjectExportFieldID.speciesName, Strings.ExportFields.speciesName, modules: [.pamAudio, .bruvVideo, .ruvImages]) { _, decision in decision?.speciesName ?? "" },
        field(ProjectExportFieldID.speciesFullName, Strings.ExportFields.speciesFullName, modules: [.pamAudio, .bruvVideo, .ruvImages]) { _, decision in decision?.speciesFullName ?? "" },
        field(ProjectExportFieldID.durationSeconds, Strings.ExportFields.durationSeconds, modules: [.pamAudio, .bruvVideo]) { file, _ in number(file.durationSeconds) },
        field(ProjectExportFieldID.clipStartSeconds, Strings.ExportFields.clipStartSeconds, modules: [.pamAudio]) { file, _ in number(file.clipStartSeconds) },
        field(ProjectExportFieldID.clipDurationSeconds, Strings.ExportFields.clipDurationSeconds, modules: [.pamAudio]) { file, _ in number(file.clipDurationSeconds) },
        field(ProjectExportFieldID.sampleRateHz, Strings.ExportFields.sampleRateHz, modules: [.pamAudio]) { file, _ in int(file.sampleRateHz) },
        field(ProjectExportFieldID.channels, Strings.ExportFields.channels, modules: [.pamAudio]) { file, _ in int(file.channels) },
        field(ProjectExportFieldID.bitDepth, Strings.ExportFields.bitDepth, modules: [.pamAudio]) { file, _ in int(file.bitDepth) },
        field(ProjectExportFieldID.peakDBFS, Strings.ExportFields.peakDBFS, modules: [.pamAudio]) { file, _ in number(file.peakDBFS) },
        field(ProjectExportFieldID.rmsDBFS, Strings.ExportFields.rmsDBFS, modules: [.pamAudio]) { file, _ in number(file.rmsDBFS) },
        field(ProjectExportFieldID.detector, Strings.ExportFields.detector, modules: [.pamAudio]) { file, _ in file.format ?? "" },
        field(ProjectExportFieldID.frameNumber, Strings.ExportFields.frameNumber, modules: [.bruvVideo]) { file, _ in int(file.frameNumber) },
        field(ProjectExportFieldID.trackID, Strings.ExportFields.trackID, modules: [.bruvVideo]) { file, _ in int(file.trackID) },
        field(ProjectExportFieldID.maxN, Strings.ExportFields.maxN, modules: [.bruvVideo, .ruvImages]) { file, decision in int(decision?.userMaxN ?? file.maxN) },
        field(ProjectExportFieldID.confidence, Strings.ExportFields.confidence, modules: [.bruvVideo]) { file, _ in number(file.sharkTrackConfidence) },
        field(ProjectExportFieldID.frameCount, Strings.ExportFields.frameCount, modules: [.bruvVideo]) { file, _ in int(file.frameCount) },
        field(ProjectExportFieldID.frameRate, Strings.ExportFields.frameRate, modules: [.bruvVideo]) { file, _ in number(file.frameRate) },
        field(ProjectExportFieldID.width, Strings.ExportFields.width, modules: [.bruvVideo, .ruvImages]) { file, _ in int(file.width) },
        field(ProjectExportFieldID.height, Strings.ExportFields.height, modules: [.bruvVideo, .ruvImages]) { file, _ in int(file.height) },
        field(ProjectExportFieldID.format, Strings.ExportFields.format, modules: [.pamAudio, .bruvVideo, .ruvImages]) { file, _ in file.format ?? "" },
        field(ProjectExportFieldID.sizeBytes, Strings.ExportFields.sizeBytes, modules: [.pamAudio, .bruvVideo, .ruvImages]) { file, _ in "\(file.sizeBytes)" },
        field(ProjectExportFieldID.qualityFlag, Strings.ExportFields.qualityFlag, modules: [.bruvVideo, .ruvImages]) { file, _ in file.qualityFlag },
        field(ProjectExportFieldID.qualityReasons, Strings.ExportFields.qualityReasons, modules: [.bruvVideo, .ruvImages]) { file, _ in file.qualityReasons.joined(separator: PAMExportSeparators.fieldList) }
    ]

    private static func field(
        _ id: String,
        _ title: String,
        modules: Set<WorkflowModule>,
        value: @escaping (ProjectScanFile, ManualAuditDecision?) -> String
    ) -> ProjectExportField {
        ProjectExportField(id: id, title: title, modules: modules) { _, file, decision in
            value(file, decision)
        }
    }

    private static func projectField(
        _ id: String,
        _ title: String,
        modules: Set<WorkflowModule>,
        value: @escaping (Project) -> String
    ) -> ProjectExportField {
        ProjectExportField(id: id, title: title, modules: modules) { project, _, _ in
            value(project)
        }
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(format: "%.6f", $0) } ?? ""
    }

    private static func int(_ value: Int?) -> String {
        value.map(String.init) ?? ""
    }

    private static func eventID(_ file: ProjectScanFile) -> String {
        file.relativePath
            .replacingOccurrences(of: "\(PAMGuardPreview.relativeEventDirectory)/", with: "")
            .replacingOccurrences(of: "\(ProjectFileNames.pamguardDirectory)/\(ProjectFileNames.detectionsDirectory)/", with: "")
            .replacingOccurrences(of: ".\(PAMExportFileNames.spectrogramImageExtension)", with: "")
    }

    private static func sourceMediaDisplayName(for file: ProjectScanFile) -> String {
        if let sourceVideo = file.sourceVideo, !sourceVideo.isEmpty {
            return sourceVideo
        }
        let components = file.relativePath.split(separator: "/").map(String.init)
        if let internalResultsIndex = components.firstIndex(of: "internal_results"),
           components.indices.contains(internalResultsIndex + 1) {
            return components[internalResultsIndex + 1]
        }
        return isSharkTrackOutputName(file.fileName) ? "" : file.fileName
    }

    private static func isSharkTrackOutputName(_ name: String) -> Bool {
        let lowercased = name.lowercased()
        return lowercased.contains("elasmobranch") || lowercased.contains("sharktrack")
    }

    private static func metadataValue(_ file: ProjectScanFile, key: String) -> String {
        let prefix = "\(key):"
        return file.qualityReasons
            .first { reason in
                reason.lowercased().hasPrefix(prefix.lowercased())
            }
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }
}
