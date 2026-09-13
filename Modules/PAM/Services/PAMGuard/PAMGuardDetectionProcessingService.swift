//
//  PAMGuardDetectionProcessingService.swift
//  PAMFlow
//
//  Created by Dory on 03/07/2026.
//

import AppKit
import AVFoundation
import Foundation
import SQLite3

/// PAMGuard detection import boundary.
@MainActor
protocol PAMGuardDetectionProcessingServicing {
    func process(
        project: Project,
        originalSummary: ProjectScanSummary,
        onProgress: @escaping @Sendable (PAMGuardDetectionProcessingService.Progress) -> Void
    ) async throws -> ProjectScanSummary
}

/// Imports PAMGuard run outputs into the native detection-review workflow.
final class PAMGuardDetectionProcessingService: PAMGuardDetectionProcessingServicing {
    private nonisolated static let eventMergeGapSeconds = 2.0
    private nonisolated static let eventReviewPaddingSeconds = 2.0

    struct Progress: Sendable {
        let message: String
        let current: Int?
        let total: Int?

        var fractionCompleted: Double? {
            guard let current, let total, total > 0 else { return nil }
            return min(Double(current) / Double(total), 1)
        }
    }

    enum ProcessingError: LocalizedError {
        case missingProjectFolder
        case missingInputFolder
        case missingDatabase
        case missingBinaryFolder
        case sqliteOpenFailed(String)
        case noDetectionsFound

        var errorDescription: String? {
            switch self {
            case .missingProjectFolder:
                PAMStrings.DetectionError.missingProjectFolder
            case .missingInputFolder:
                PAMStrings.DetectionError.missingInputFolder
            case .missingDatabase:
                PAMStrings.DetectionError.missingDatabase
            case .missingBinaryFolder:
                PAMStrings.DetectionError.missingBinaryFolder
            case .sqliteOpenFailed(let message):
                String(format: PAMStrings.DetectionError.sqliteOpenFailedFormat, message)
            case .noDetectionsFound:
                PAMStrings.DetectionError.noDetectionsFound
            }
        }
    }

    func process(
        project: Project,
        originalSummary: ProjectScanSummary,
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async throws -> ProjectScanSummary {
        guard let projectRootURL = project.rootFolderURL else {
            throw ProcessingError.missingProjectFolder
        }
        guard let inputFolderURL = project.inputFolderURL else {
            throw ProcessingError.missingInputFolder
        }

        let accessedProject = projectRootURL.startAccessingSecurityScopedResource()
        let accessedInput = inputFolderURL.startAccessingSecurityScopedResource()
        defer {
            if accessedProject { projectRootURL.stopAccessingSecurityScopedResource() }
            if accessedInput { inputFolderURL.stopAccessingSecurityScopedResource() }
        }

        onProgress(Progress(message: PAMStrings.DetectionProgress.readingBinary, current: nil, total: nil))
        let sourceFiles = originalSummary.files
            .filter(\.readable)
            .filter(isAudioSourceFile)

        var detections = try readBinaryDetections(
            projectRootURL: projectRootURL,
            sourceFiles: sourceFiles,
            onProgress: onProgress
        )
        if detections.isEmpty, let dbURL = try? databaseURL(projectRootURL: projectRootURL) {
            onProgress(Progress(message: PAMStrings.DetectionProgress.readingDatabaseFallback, current: nil, total: nil))
            detections = try readDetections(dbURL: dbURL)
        }
        guard !detections.isEmpty else {
            throw ProcessingError.noDetectionsFound
        }

        onProgress(Progress(message: PAMStrings.DetectionProgress.groupingEvents, current: nil, total: nil))
        let events = detectionEvents(from: detections, sourceFiles: sourceFiles)
        guard !events.isEmpty else {
            throw ProcessingError.noDetectionsFound
        }

        let previewFolderURL = projectRootURL
            .appendingPathComponent(ProjectFileNames.workDirectory)
            .appendingPathComponent(PAMProjectFileNames.pamguardDetectionPreviewDirectory)
        try FileManager.default.createDirectory(at: previewFolderURL, withIntermediateDirectories: true)

        let reviewFiles = try events.enumerated().map { offset, event in
            let index = offset + 1
            onProgress(Progress(
                message: String(format: PAMStrings.DetectionProgress.preparingEventFormat, index, events.count),
                current: index,
                total: events.count
            ))
            return try reviewFile(
                event: event,
                inputFolderURL: inputFolderURL,
                previewFolderURL: previewFolderURL,
                projectRootURL: projectRootURL,
                index: index
            )
        }

        let summary = ProjectScanSummary(
            projectName: originalSummary.projectName,
            recorderID: originalSummary.recorderID,
            inputFolder: inputFolderURL.path,
            scannedAt: .now,
            fileCount: reviewFiles.count,
            readableFileCount: reviewFiles.filter(\.readable).count,
            unreadableFileCount: reviewFiles.filter { !$0.readable }.count,
            totalSizeBytes: reviewFiles.reduce(0) { $0 + $1.sizeBytes },
            durationMinSeconds: reviewFiles.compactMap(\.durationSeconds).min(),
            durationMaxSeconds: reviewFiles.compactMap(\.durationSeconds).max(),
            durationModeSeconds: nil,
            formats: sortedUniqueStrings(reviewFiles.compactMap(\.format)),
            qualityWarningCount: 0,
            warnings: [],
            attributes: [
                PAMScanAttribute.sampleRatesHz: .ints(sortedUnique(reviewFiles.compactMap(\.sampleRateHz))),
                PAMScanAttribute.channelCounts: .ints(sortedUnique(reviewFiles.compactMap(\.channels))),
                PAMScanAttribute.bitDepths: .ints(sortedUnique(reviewFiles.compactMap(\.bitDepth)))
            ],
            files: reviewFiles
        )

        try ProjectScanService.writeSummary(summary, projectRootURL: projectRootURL)
        onProgress(Progress(message: PAMStrings.DetectionProgress.eventsReady, current: events.count, total: events.count))
        return summary
    }

    nonisolated private func databaseURL(projectRootURL: URL) throws -> URL {
        let dbFolderURL = projectRootURL
            .appendingPathComponent(PAMProjectFileNames.pamguardDirectory)
            .appendingPathComponent(PAMProjectFileNames.pamguardDatabaseDirectory)
        let candidates = ((try? FileManager.default.contentsOfDirectory(
            at: dbFolderURL,
            includingPropertiesForKeys: nil
        )) ?? [])
            .filter { PAMMediaFileExtensions.pamguardDatabase.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        guard let first = candidates.first else {
            throw ProcessingError.missingDatabase
        }
        return first
    }

    nonisolated private func binaryFolderURL(projectRootURL: URL) throws -> URL {
        let binaryFolderURL = projectRootURL
            .appendingPathComponent(PAMProjectFileNames.pamguardDirectory)
            .appendingPathComponent(PAMProjectFileNames.pamguardBinaryDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: binaryFolderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProcessingError.missingBinaryFolder
        }
        return binaryFolderURL
    }

    nonisolated private func readBinaryDetections(
        projectRootURL: URL,
        sourceFiles: [ProjectScanFile],
        onProgress: @escaping @Sendable (Progress) -> Void
    ) throws -> [PAMGuardDetection] {
        let binaryFolderURL = try binaryFolderURL(projectRootURL: projectRootURL)
        let binaryFiles = ((FileManager.default.enumerator(
            at: binaryFolderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.allObjects as? [URL]) ?? [])
            .filter { PAMMediaFileExtensions.pamguardBinary.contains($0.pathExtension.lowercased()) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }

        var detections: [PAMGuardDetection] = []
        for (offset, fileURL) in binaryFiles.enumerated() {
            onProgress(Progress(
                message: String(format: PAMStrings.DetectionProgress.decodingBinaryFileFormat, offset + 1, binaryFiles.count),
                current: offset + 1,
                total: binaryFiles.count
            ))
            detections.append(contentsOf: try readBinaryDetections(
                fileURL: fileURL,
                binaryFolderURL: binaryFolderURL,
                sourceFiles: sourceFiles
            ))
        }

        return detections.sorted {
            if $0.utcMilliseconds == $1.utcMilliseconds {
                return $0.id < $1.id
            }
            return ($0.utcMilliseconds ?? 0) < ($1.utcMilliseconds ?? 0)
        }
    }

    nonisolated private func readBinaryDetections(
        fileURL: URL,
        binaryFolderURL: URL,
        sourceFiles: [ProjectScanFile]
    ) throws -> [PAMGuardDetection] {
        let data = try Data(contentsOf: fileURL)
        let relativeBinaryPath = relativePath(fileURL, from: binaryFolderURL)
        var moduleName = moduleName(fromBinaryFile: fileURL)
        var moduleType = ""
        var streamName = moduleName
        var fileStartUTCMilliseconds: Double?
        var firstDataUTCMilliseconds: Double?
        var output: [PAMGuardDetection] = []
        var offset = 0
        var objectIndex = 0

        while offset + 8 <= data.count {
            let startOffset = offset
            guard let objectLength = data.readInt32(at: offset),
                  let objectType = data.readInt32(at: offset + 4),
                  objectLength > 0 else {
                break
            }

            var recordEnd = offset + Int(objectLength)
            if offset == 0, objectType == -1 {
                recordEnd = offset + 4 + Int(objectLength)
            }
            let payloadStart = offset + 8
            let payloadEnd = min(max(payloadStart, recordEnd), data.count)
            guard payloadStart <= payloadEnd else {
                break
            }

            let payload = data[payloadStart..<payloadEnd]
            objectIndex += 1

            if objectType == -1 {
                let header = parseBinaryHeader(payload)
                moduleName = header.moduleName ?? moduleName
                moduleType = header.moduleType ?? moduleType
                streamName = header.streamName ?? streamName
                fileStartUTCMilliseconds = header.fileStartUTCMilliseconds
            } else if objectType > 0 {
                let utc = payload.readInt64(atRelativeOffset: 0)
                    .map(Double.init)
                    .flatMap { plausibleUTCMilliseconds($0) ? $0 : nil }
                if firstDataUTCMilliseconds == nil {
                    firstDataUTCMilliseconds = utc
                }
                let source = binarySourceFile(
                    relativeBinaryPath: relativeBinaryPath,
                    utcMilliseconds: utc,
                    fileStartUTCMilliseconds: fileStartUTCMilliseconds,
                    firstDataUTCMilliseconds: firstDataUTCMilliseconds,
                    sourceFiles: sourceFiles
                )
                let beginTime = beginTimeSeconds(
                    utcMilliseconds: utc,
                    fileStartUTCMilliseconds: fileStartUTCMilliseconds,
                    firstDataUTCMilliseconds: firstDataUTCMilliseconds,
                    source: source
                )
                let id = binaryDetectionID(
                    relativeBinaryPath: relativeBinaryPath,
                    byteOffset: startOffset,
                    objectType: Int(objectType),
                    utcMilliseconds: utc
                )
                output.append(PAMGuardDetection(
                    id: id,
                    table: streamName.isEmpty ? moduleName : streamName,
                    utcMilliseconds: utc,
                    durationSeconds: nil,
                    lowFrequencyHz: nil,
                    highFrequencyHz: nil,
                    confidence: nil,
                    rawValues: [
                        "source_type": "pamguard_binary",
                        "source_binary_file": relativeBinaryPath,
                        "source_byte_offset": "\(startOffset)",
                        "object_type": "\(objectType)",
                        "object_index": "\(objectIndex)",
                        "module_name": moduleName,
                        "module_type": moduleType,
                        "relative_audio_path": source?.relativePath ?? "",
                        "file_name": source?.fileName ?? "",
                        "begin_time_s": beginTime.map { String(format: "%.6f", $0) } ?? "",
                        "parser_status": utc == nil ? "unsupported_payload" : "partial",
                        "payload_hex_prefix_after_time": payload.dropFirst(min(payload.count, 8)).prefix(64).hexString
                    ].filter { !$0.value.isEmpty }
                ))
            }

            guard recordEnd > offset else { break }
            offset = min(recordEnd, data.count)
        }

        return output
    }

    nonisolated private func readDetections(dbURL: URL) throws -> [PAMGuardDetection] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
            if db != nil { sqlite3_close(db) }
            throw ProcessingError.sqliteOpenFailed(message)
        }
        defer { sqlite3_close(db) }

        var detections: [PAMGuardDetection] = []
        for table in tables(in: db) {
            let columns = columns(in: db, table: table)
            guard let timeColumn = timeColumn(in: columns),
                  isDetectorTable(table: table, columns: columns) else {
                continue
            }
            detections.append(contentsOf: rows(in: db, table: table, columns: columns, timeColumn: timeColumn))
        }

        return detections.sorted {
            if $0.utcMilliseconds == $1.utcMilliseconds {
                return $0.id < $1.id
            }
            return ($0.utcMilliseconds ?? 0) < ($1.utcMilliseconds ?? 0)
        }
    }

    nonisolated private func tables(in db: OpaquePointer?) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var output: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                output.append(String(cString: text))
            }
        }
        return output
    }

    nonisolated private func columns(in db: OpaquePointer?, table: String) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\")", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var output: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 1) {
                output.append(String(cString: text))
            }
        }
        return output
    }

    nonisolated private func rows(in db: OpaquePointer?, table: String, columns: [String], timeColumn: String) -> [PAMGuardDetection] {
        let quotedColumns = columns.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: ", ")
        let quotedTable = "\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\""
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT \(quotedColumns) FROM \(quotedTable) LIMIT 5000", -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var output: [PAMGuardDetection] = []
        var rowIndex = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            rowIndex += 1
            var values: [String: String] = [:]
            for index in columns.indices {
                if let text = sqlite3_column_text(statement, Int32(index)) {
                    values[columns[index]] = String(cString: text)
                }
            }
            let utc = doubleValue(values[timeColumn])
            let duration = durationValue(values: values)
            output.append(PAMGuardDetection(
                id: "\(table)-\(rowIndex)",
                table: table,
                utcMilliseconds: utc,
                durationSeconds: duration,
                lowFrequencyHz: firstDouble(values: values, names: ["LowFrequency", "LowFreq", "MinFreq", "f1", "low_frequency"]),
                highFrequencyHz: firstDouble(values: values, names: ["HighFrequency", "HighFreq", "MaxFreq", "f2", "high_frequency"]),
                confidence: firstDouble(values: values, names: ["Score", "Confidence", "Probability"]),
                rawValues: values
            ))
        }
        return output
    }

    nonisolated private func isDetectorTable(table: String, columns: [String]) -> Bool {
        let lower = table.lowercased()
        guard !lower.contains("settings"),
              !lower.contains("module"),
              !lower.contains("hydrophone"),
              !lower.contains("streamer") else {
            return false
        }
        let normalized = Set(columns.map { $0.lowercased() })
        return normalized.contains { column in
            column.contains("utc") || column.contains("time")
        } && (lower.contains("click") || lower.contains("whistle") || lower.contains("detection") || lower.contains("event"))
    }

    nonisolated private func timeColumn(in columns: [String]) -> String? {
        let preferred = ["UTC", "utc", "StartTime", "start_time", "Time", "time"]
        for name in preferred {
            if let match = columns.first(where: { $0 == name }) {
                return match
            }
        }
        return columns.first { $0.lowercased().contains("utc") || $0.lowercased().contains("time") }
    }

    nonisolated private func bestSourceFile(for detection: PAMGuardDetection, from files: [ProjectScanFile]) -> ProjectScanFile? {
        if let relativePath = detection.rawValues["relative_audio_path"],
           let match = files.first(where: { $0.relativePath == relativePath }) {
            return match
        }
        guard let utcMilliseconds = detection.utcMilliseconds else { return files.first }
        let detectionDate = Date(timeIntervalSince1970: utcMilliseconds / 1000.0)
        return files.first { file in
            guard let start = dateFromFilename(file.fileName),
                  let duration = file.durationSeconds else { return false }
            return detectionDate >= start && detectionDate <= start.addingTimeInterval(duration + 1)
        }
    }

    nonisolated private func detectionEvents(
        from detections: [PAMGuardDetection],
        sourceFiles: [ProjectScanFile]
    ) -> [PAMGuardEvent] {
        let normalized = detections.compactMap { detection -> NormalizedDetection? in
            guard let source = bestSourceFile(for: detection, from: sourceFiles),
                  let range = normalizedTimeRange(for: detection, source: source) else {
                return nil
            }
            return NormalizedDetection(
                id: detection.id,
                source: source,
                detectorLabel: detectorLabel(for: detection),
                kind: detectorKind(for: detection),
                startTime: range.start,
                endTime: range.end,
                lowFrequencyHz: detection.lowFrequencyHz,
                highFrequencyHz: detection.highFrequencyHz,
                confidence: detection.confidence
            )
        }

        var candidates = nonClickCandidates(from: normalized)
        candidates.append(contentsOf: clickBoutCandidates(from: normalized))
        guard !candidates.isEmpty else { return [] }

        let merged = mergeCandidates(candidates)
            .flatMap(splitLongEvent)
            .map(scoredEvent)
            .filter { $0.score > 0 }

        return Dictionary(grouping: merged, by: \.fileID)
            .values
            .flatMap { events in
                events.sorted {
                    if $0.score == $1.score {
                        return $0.startTime < $1.startTime
                    }
                    return $0.score > $1.score
                }
                .prefix(20)
            }
            .sorted {
                if $0.fileID == $1.fileID {
                    return $0.startTime < $1.startTime
                }
                return $0.fileID.localizedStandardCompare($1.fileID) == .orderedAscending
            }
    }

    nonisolated private func normalizedTimeRange(
        for detection: PAMGuardDetection,
        source: ProjectScanFile
    ) -> (start: Double, end: Double)? {
        let sourceDuration = source.durationSeconds ?? .greatestFiniteMagnitude
        let start = detection.clipStartSeconds ?? relativeStartTime(detection: detection, source: source)
        guard let start, start.isFinite else { return nil }
        let duration = max(0, detection.durationSeconds ?? detection.clipDurationSeconds ?? 0)
        let end = min(max(start, start + duration), sourceDuration)
        return (max(0, min(start, sourceDuration)), max(0, end))
    }

    nonisolated private func relativeStartTime(detection: PAMGuardDetection, source: ProjectScanFile) -> Double? {
        guard let utcMilliseconds = detection.utcMilliseconds,
              let startDate = dateFromFilename(source.fileName) else {
            return nil
        }
        let detectionDate = Date(timeIntervalSince1970: utcMilliseconds / 1000.0)
        let seconds = detectionDate.timeIntervalSince(startDate)
        guard seconds >= 0 else { return nil }
        if let duration = source.durationSeconds, seconds > duration + 1 {
            return nil
        }
        return seconds
    }

    nonisolated private func nonClickCandidates(from detections: [NormalizedDetection]) -> [EventCandidate] {
        detections.compactMap { detection in
            switch detection.kind {
            case .clickTrain:
                return EventCandidate(
                    source: detection.source,
                    startTime: detection.startTime,
                    endTime: detection.endTime,
                    clickCount: 0,
                    clickBoutCount: 0,
                    clickTrainCount: 1,
                    whistleCount: 0,
                    detectorLabels: [detection.detectorLabel],
                    lowFrequencyHz: detection.lowFrequencyHz,
                    highFrequencyHz: detection.highFrequencyHz,
                    confidence: detection.confidence
                )
            case .whistle:
                return EventCandidate(
                    source: detection.source,
                    startTime: detection.startTime,
                    endTime: detection.endTime,
                    clickCount: 0,
                    clickBoutCount: 0,
                    clickTrainCount: 0,
                    whistleCount: 1,
                    detectorLabels: [detection.detectorLabel],
                    lowFrequencyHz: detection.lowFrequencyHz,
                    highFrequencyHz: detection.highFrequencyHz,
                    confidence: detection.confidence
                )
            case .click, .other:
                return nil
            }
        }
    }

    nonisolated private func clickBoutCandidates(from detections: [NormalizedDetection]) -> [EventCandidate] {
        let clicks = detections
            .filter { $0.kind == .click }
            .sorted {
                if $0.fileID == $1.fileID {
                    return $0.startTime < $1.startTime
                }
                return $0.fileID.localizedStandardCompare($1.fileID) == .orderedAscending
            }
        var candidates: [EventCandidate] = []
        var bout: [NormalizedDetection] = []

        func finishBout() {
            guard let first = bout.first, let last = bout.last else {
                bout.removeAll()
                return
            }
            let duration = max(0, last.endTime - first.startTime)
            guard bout.count >= 5, duration >= 0.1 else {
                bout.removeAll()
                return
            }
            candidates.append(EventCandidate(
                source: first.source,
                startTime: first.startTime,
                endTime: max(first.startTime, last.endTime),
                clickCount: bout.count,
                clickBoutCount: 1,
                clickTrainCount: 0,
                whistleCount: 0,
                detectorLabels: uniqueHumanLabels(bout.map(\.detectorLabel)),
                lowFrequencyHz: bout.compactMap(\.lowFrequencyHz).min(),
                highFrequencyHz: bout.compactMap(\.highFrequencyHz).max(),
                confidence: bout.compactMap(\.confidence).max()
            ))
            bout.removeAll()
        }

        for click in clicks {
            if let last = bout.last,
               (click.fileID != last.fileID || click.startTime - last.endTime > 1.0) {
                finishBout()
            }
            bout.append(click)
        }
        finishBout()
        return candidates
    }

    nonisolated private func mergeCandidates(_ candidates: [EventCandidate]) -> [EventCandidate] {
        let sorted = candidates.sorted {
            if $0.fileID == $1.fileID {
                return $0.startTime < $1.startTime
            }
            return $0.fileID.localizedStandardCompare($1.fileID) == .orderedAscending
        }
        var merged: [EventCandidate] = []
        for candidate in sorted {
            guard var last = merged.last,
                  last.fileID == candidate.fileID,
                  candidate.startTime - last.endTime <= Self.eventMergeGapSeconds else {
                merged.append(candidate)
                continue
            }
            last.merge(candidate)
            merged[merged.count - 1] = last
        }
        return merged
    }

    nonisolated private func splitLongEvent(_ candidate: EventCandidate) -> [EventCandidate] {
        let sourceDuration = candidate.source.durationSeconds ?? max(candidate.endTime + Self.eventReviewPaddingSeconds, candidate.startTime + 1.0)
        var output = candidate
        output.reviewStartTime = max(0, candidate.startTime - Self.eventReviewPaddingSeconds)
        output.reviewEndTime = min(sourceDuration, candidate.endTime + Self.eventReviewPaddingSeconds)
        output.expandEventDuration(toAtLeast: 1.0, sourceDuration: sourceDuration)
        return [output]
    }

    nonisolated private func scoredEvent(_ candidate: EventCandidate) -> PAMGuardEvent {
        let duration = max(0, candidate.endTime - candidate.startTime)
        let qualityFlags = qualityFlags(for: candidate.source)
        var score = min(Double(candidate.clickCount) / 20.0, 5.0)
        if candidate.clickTrainCount > 0 { score += 5 }
        if candidate.whistleCount > 0 { score += 3 }
        if duration >= 1.0, duration <= 60.0 { score += 2 }
        if qualityFlags.contains("Noisy") { score -= 3 }
        if !qualityFlags.filter({ $0.contains("Clipping") || $0.contains("Quality") }).isEmpty { score -= 3 }

        let evidenceTypes = evidenceTypes(for: candidate)
        let id = eventID(fileID: candidate.fileID, startTime: candidate.reviewStartTime, suffix: candidate.idSuffix)
        return PAMGuardEvent(
            id: id,
            fileID: candidate.fileID,
            source: candidate.source,
            startTime: candidate.startTime,
            endTime: candidate.endTime,
            reviewStartTime: candidate.reviewStartTime,
            reviewEndTime: candidate.reviewEndTime,
            score: score,
            evidenceTypes: evidenceTypes,
            detectorLabels: candidate.detectorLabels,
            clickCount: candidate.clickCount,
            clickBoutCount: candidate.clickBoutCount,
            clickTrainCount: candidate.clickTrainCount,
            whistleCount: candidate.whistleCount,
            qualityFlags: qualityFlags,
            lowFrequencyHz: candidate.lowFrequencyHz,
            highFrequencyHz: candidate.highFrequencyHz,
            confidence: candidate.confidence
        )
    }

    nonisolated private func reviewFile(
        event: PAMGuardEvent,
        inputFolderURL: URL,
        previewFolderURL: URL,
        projectRootURL: URL,
        index: Int
    ) throws -> ProjectScanFile {
        let fileName = "\(PAMGuardPreview.filePrefix)-\(String(format: "%04d", index)).\(PAMGuardPreview.fileExtension)"
        let previewURL = previewFolderURL.appendingPathComponent(fileName)
        try renderPreview(event: event, to: previewURL)
        let previewRelativePath = relativePath(previewURL, from: projectRootURL)
        let eventDuration = max(0, event.endTime - event.startTime)
        let reviewDuration = max(0.05, event.reviewEndTime - event.reviewStartTime)

        return ProjectScanFile(
            fileName: "\(PAMGuardPreview.eventQualityFlag) \(index)",
            relativePath: "\(PAMGuardPreview.relativeEventDirectory)/\(event.id)",
            sizeBytes: 0,
            readable: true,
            readError: "",
            durationSeconds: eventDuration,
            format: event.evidenceTypes.joined(separator: ", "),
            qualityFlag: event.qualityFlags.isEmpty ? PAMGuardPreview.eventQualityFlag : event.qualityFlags.joined(separator: ", "),
            qualityReasons: event.qualityReasons,
            attributes: [
                PAMScanAttribute.detectionID: .int(index),
                PAMScanAttribute.confidence: .double(event.score),
                PAMScanAttribute.status: .string(PAMScanStatus.pamguard),
                PAMScanAttribute.sourceMedia: .string(event.fileID),
                PAMScanAttribute.previewPath: .string(previewRelativePath),
                PAMScanAttribute.previewWidth: .int(1280),
                PAMScanAttribute.previewHeight: .int(720),
                PAMScanAttribute.clipStartSeconds: .double(event.reviewStartTime),
                PAMScanAttribute.clipDurationSeconds: .double(reviewDuration)
            ]
            .merging(event.source.sampleRateHz.map { [PAMScanAttribute.sampleRateHz: .int($0)] } ?? [:]) { current, _ in current }
            .merging(event.source.channels.map { [PAMScanAttribute.channels: .int($0)] } ?? [:]) { current, _ in current }
            .merging(event.source.bitDepth.map { [PAMScanAttribute.bitDepth: .int($0)] } ?? [:]) { current, _ in current }
        )
    }

    nonisolated private func renderPreview(event: PAMGuardEvent, to url: URL) throws {
        let size = CGSize(width: 1280, height: 720)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()

        let title = PAMGuardPreview.fallbackTitle
        let lines = [
            "Evidence: \(event.evidenceTypes.joined(separator: ", "))",
            "Detectors: \(event.detectorLabels.joined(separator: ", "))",
            "Source: \(event.source.fileName)",
            "Time: \(formatSeconds(event.startTime)) to \(formatSeconds(event.endTime))",
            "Review window: \(formatSeconds(event.reviewStartTime)) to \(formatSeconds(event.reviewEndTime))",
            "Score: \(String(format: "%.1f", event.score))",
            "Counts: \(event.countSummary)",
            "Frequency: \(frequencyText(low: event.lowFrequencyHz, high: event.highFrequencyHz))"
        ]
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 52),
            .foregroundColor: NSColor.labelColor
        ]
        title.draw(at: CGPoint(x: 72, y: 600), withAttributes: titleAttributes)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 32, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        for (offset, line) in lines.enumerated() {
            line.draw(at: CGPoint(x: 72, y: 500 - offset * 58), withAttributes: attributes)
        }

        NSColor.systemBlue.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: NSRect(x: 72, y: 80, width: 1136, height: 120), xRadius: 16, yRadius: 16).fill()
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 180, y: 118, width: 220, height: 44), xRadius: 10, yRadius: 10).fill()

        image.unlockFocus()

        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }

    nonisolated private func frequencyText(_ detection: PAMGuardDetection) -> String {
        frequencyText(low: detection.lowFrequencyHz, high: detection.highFrequencyHz)
    }

    nonisolated private func frequencyText(low: Double?, high: Double?) -> String {
        switch (low, high) {
        case let (low?, high?):
            return "\(Int(low.rounded()))-\(Int(high.rounded())) Hz"
        case let (low?, nil):
            return "\(Int(low.rounded())) Hz"
        case let (nil, high?):
            return "\(Int(high.rounded())) Hz"
        default:
            return "Unknown"
        }
    }

    nonisolated private func durationValue(values: [String: String]) -> Double? {
        if let duration = firstDouble(values: values, names: ["Duration", "duration", "DurationSeconds", "duration_s"]) {
            return duration > 1000 ? duration / 1000.0 : duration
        }
        if let start = firstDouble(values: values, names: ["StartTime", "start_time", "Time"]),
           let end = firstDouble(values: values, names: ["EndTime", "end_time"]) {
            return abs(end - start) > 1000 ? abs(end - start) / 1000.0 : abs(end - start)
        }
        return nil
    }

    nonisolated private func detectorKind(for detection: PAMGuardDetection) -> DetectorKind {
        let text = [
            detection.table,
            detection.rawValues["module_type"],
            detection.rawValues["module_name"],
            detection.rawValues["Pamguard_Module"],
            detection.rawValues["Detector"],
            detection.rawValues["detector_type"]
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        if text.contains("click") && text.contains("train") { return .clickTrain }
        if text.contains("whistle") || text.contains("moan") { return .whistle }
        if text.contains("click") { return .click }
        return .other
    }

    nonisolated private func detectorLabel(for detection: PAMGuardDetection) -> String {
        let candidates = [
            detection.table,
            detection.rawValues["module_name"],
            detection.rawValues["module_type"],
            detection.rawValues["Detector"],
            detection.rawValues["detector_type"]
        ]
        let label = candidates
            .compactMap { $0 }
            .map(humanReadableLabel)
            .first { !$0.isEmpty }
        return label ?? "PAMGuard detector"
    }

    nonisolated private func evidenceTypes(for candidate: EventCandidate) -> [String] {
        var output: [String] = []
        if candidate.clickTrainCount > 0 { output.append("Click train") }
        if candidate.whistleCount > 0 { output.append("Whistle or moan") }
        if candidate.clickBoutCount > 0 { output.append("Click bout") }
        if output.isEmpty, candidate.clickCount > 0 { output.append("Individual clicks") }
        return output
    }

    nonisolated private func qualityFlags(for source: ProjectScanFile) -> [String] {
        var flags: [String] = []
        let reasons = source.qualityReasons.map { $0.lowercased() }
        if reasons.contains(where: { $0.contains("near_zero") || $0.contains("very_low") || $0.contains("noise") }) {
            flags.append("Noisy")
        }
        if reasons.contains(where: { $0.contains("clipping") || $0.contains("clipped") }) {
            flags.append("Clipping warning")
        }
        if source.qualityFlag.lowercased() != "ok" || !source.qualityReasons.isEmpty {
            flags.append("Quality warning")
        }
        return uniqueHumanLabels(flags)
    }

    nonisolated private func eventID(fileID: String, startTime: Double, suffix: String?) -> String {
        let raw = "\(fileID)-\(String(format: "%.3f", startTime))-\(suffix ?? "event")"
        return raw
            .replacingOccurrences(of: #"[^\w.-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    nonisolated private func humanReadableLabel(_ value: String) -> String {
        let spaced = value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spaced.isEmpty else { return "" }
        return spaced
            .split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                if ["PAM", "PAMGuard", "FFT"].contains(String(word)) { return String(word) }
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    nonisolated private func uniqueHumanLabels(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for label in labels.map(humanReadableLabel) where !label.isEmpty {
            let key = label.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                output.append(label)
            }
        }
        return output
    }

    nonisolated private func formatSeconds(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let remaining = seconds - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, remaining)
    }

    nonisolated private func firstDouble(values: [String: String], names: [String]) -> Double? {
        for name in names {
            if let value = values.first(where: { $0.key.lowercased() == name.lowercased() })?.value,
               let number = doubleValue(value) {
                return number
            }
        }
        return nil
    }

    nonisolated private func doubleValue(_ value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated private func dateFromFilename(_ fileName: String) -> Date? {
        let patterns: [(String, String)] = [
            (#"\d{8}_\d{6}"#, "yyyyMMdd_HHmmss"),
            (#"\d{14}"#, "yyyyMMddHHmmss")
        ]
        for (pattern, format) in patterns {
            guard let range = fileName.range(of: pattern, options: .regularExpression) else { continue }
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let date = formatter.date(from: String(fileName[range])) {
                return date
            }
        }
        return nil
    }

    nonisolated private func relativePath(_ url: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    nonisolated private func parseBinaryHeader(_ payload: Data.SubSequence) -> PAMGuardBinaryHeader {
        var offset = payload.startIndex
        _ = payload.readJavaUTF(offset: &offset)
        _ = payload.readJavaUTF(offset: &offset)
        _ = payload.readJavaUTF(offset: &offset)
        let fileStart = payload.readInt64(offset: &offset).map(Double.init)
        _ = payload.readInt64(offset: &offset)
        _ = payload.readInt32(offset: &offset)
        _ = payload.readInt64(offset: &offset)
        let moduleType = payload.readJavaUTF(offset: &offset)
        let moduleName = payload.readJavaUTF(offset: &offset)
        let streamName = payload.readJavaUTF(offset: &offset)

        return PAMGuardBinaryHeader(
            fileStartUTCMilliseconds: fileStart.flatMap { plausibleUTCMilliseconds($0) ? $0 : nil },
            moduleType: moduleType?.trimmingCharacters(in: .whitespacesAndNewlines),
            moduleName: moduleName?.trimmingCharacters(in: .whitespacesAndNewlines),
            streamName: streamName?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    nonisolated private func moduleName(fromBinaryFile url: URL) -> String {
        var stem = url.deletingPathExtension().lastPathComponent
        stem = stem.replacingOccurrences(of: #"_?\d{8}_\d{6}$"#, with: "", options: .regularExpression)
        stem = stem.replacingOccurrences(of: #"_?\d{14}$"#, with: "", options: .regularExpression)
        let name = stem.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? url.deletingLastPathComponent().lastPathComponent : name
    }

    nonisolated private func binarySourceFile(
        relativeBinaryPath: String,
        utcMilliseconds: Double?,
        fileStartUTCMilliseconds: Double?,
        firstDataUTCMilliseconds: Double?,
        sourceFiles: [ProjectScanFile]
    ) -> ProjectScanFile? {
        if let utcMilliseconds,
           let timestampMatch = bestSourceFile(
                for: PAMGuardDetection(
                    id: "",
                    table: "",
                    utcMilliseconds: utcMilliseconds,
                    durationSeconds: nil,
                    lowFrequencyHz: nil,
                    highFrequencyHz: nil,
                    confidence: nil,
                    rawValues: [:]
                ),
                from: sourceFiles
           ) {
            return timestampMatch
        }

        guard let binaryDate = dateFromFilename(relativeBinaryPath) else {
            return sourceFiles.first
        }

        let exactMatches = sourceFiles.filter { file in
            guard let start = dateFromFilename(file.fileName) else { return false }
            return abs(start.timeIntervalSince(binaryDate)) < 1
        }
        if exactMatches.count == 1 {
            return exactMatches.first
        }

        return sourceFiles
            .compactMap { file -> (file: ProjectScanFile, delta: TimeInterval)? in
                guard let start = dateFromFilename(file.fileName) else { return nil }
                return (file, abs(start.timeIntervalSince(binaryDate)))
            }
            .sorted { $0.delta < $1.delta }
            .first?
            .file
    }

    nonisolated private func isAudioSourceFile(_ file: ProjectScanFile) -> Bool {
        let audioExtensions: Set<String> = ["wav", "wave", "aif", "aiff", "flac", "mp3", "m4a", "caf"]
        return audioExtensions.contains(URL(fileURLWithPath: file.relativePath).pathExtension.lowercased())
    }

    nonisolated private func beginTimeSeconds(
        utcMilliseconds: Double?,
        fileStartUTCMilliseconds: Double?,
        firstDataUTCMilliseconds: Double?,
        source: ProjectScanFile?
    ) -> Double? {
        guard let utcMilliseconds else { return nil }
        let reference = fileStartUTCMilliseconds ?? firstDataUTCMilliseconds
        guard let reference else { return nil }
        let begin = (utcMilliseconds - reference) / 1000.0
        guard begin >= 0 else { return nil }
        if let duration = source?.durationSeconds, begin > duration + 1 {
            return nil
        }
        return begin
    }

    nonisolated private func binaryDetectionID(
        relativeBinaryPath: String,
        byteOffset: Int,
        objectType: Int,
        utcMilliseconds: Double?
    ) -> String {
        let raw = "\(relativeBinaryPath)-\(byteOffset)-\(objectType)-\(Int(utcMilliseconds ?? 0))"
        let safe = raw
            .replacingOccurrences(of: #"[^\w.-]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(safe.suffix(96))
    }

    nonisolated private func plausibleUTCMilliseconds(_ value: Double) -> Bool {
        let date = Date(timeIntervalSince1970: value / 1000.0)
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        return (1990...2100).contains(year)
    }
}

nonisolated private enum DetectorKind {
    case click
    case clickTrain
    case whistle
    case other
}

nonisolated private struct NormalizedDetection {
    let id: String
    let source: ProjectScanFile
    let detectorLabel: String
    let kind: DetectorKind
    var startTime: Double
    var endTime: Double
    let lowFrequencyHz: Double?
    let highFrequencyHz: Double?
    let confidence: Double?

    var fileID: String { source.relativePath }
}

nonisolated private struct EventCandidate {
    let source: ProjectScanFile
    var startTime: Double
    var endTime: Double
    var clickCount: Int
    var clickBoutCount: Int
    var clickTrainCount: Int
    var whistleCount: Int
    var detectorLabels: [String]
    var lowFrequencyHz: Double?
    var highFrequencyHz: Double?
    var confidence: Double?
    var reviewStartTime: Double = 0
    var reviewEndTime: Double = 0
    var idSuffix: String?

    var fileID: String { source.relativePath }

    mutating func merge(_ other: EventCandidate) {
        startTime = min(startTime, other.startTime)
        endTime = max(endTime, other.endTime)
        clickCount += other.clickCount
        clickBoutCount += other.clickBoutCount
        clickTrainCount += other.clickTrainCount
        whistleCount += other.whistleCount
        detectorLabels = uniqueLabels(detectorLabels + other.detectorLabels)
        lowFrequencyHz = [lowFrequencyHz, other.lowFrequencyHz].compactMap { $0 }.min()
        highFrequencyHz = [highFrequencyHz, other.highFrequencyHz].compactMap { $0 }.max()
        confidence = [confidence, other.confidence].compactMap { $0 }.max()
    }

    mutating func expandEventDuration(toAtLeast minimumDuration: Double, sourceDuration: Double) {
        guard minimumDuration > 0, sourceDuration >= minimumDuration else { return }
        let currentDuration = max(0, endTime - startTime)
        guard currentDuration < minimumDuration else { return }

        let midpoint = (startTime + endTime) / 2
        var expandedStart = midpoint - minimumDuration / 2
        var expandedEnd = midpoint + minimumDuration / 2

        if expandedStart < 0 {
            expandedEnd += -expandedStart
            expandedStart = 0
        }
        if expandedEnd > sourceDuration {
            expandedStart -= expandedEnd - sourceDuration
            expandedEnd = sourceDuration
        }

        startTime = max(0, expandedStart)
        endTime = min(sourceDuration, max(expandedEnd, startTime + minimumDuration))
    }

    private func uniqueLabels(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for label in labels {
            let key = label.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                output.append(label)
            }
        }
        return output
    }
}

nonisolated private struct PAMGuardEvent {
    let id: String
    let fileID: String
    let source: ProjectScanFile
    let startTime: Double
    let endTime: Double
    let reviewStartTime: Double
    let reviewEndTime: Double
    let score: Double
    let evidenceTypes: [String]
    let detectorLabels: [String]
    let clickCount: Int
    let clickBoutCount: Int
    let clickTrainCount: Int
    let whistleCount: Int
    let qualityFlags: [String]
    let lowFrequencyHz: Double?
    let highFrequencyHz: Double?
    let confidence: Double?

    var qualityReasons: [String] {
        [
            "PAMGuard event",
            "Review status: Unreviewed",
            "File: \(fileID)",
            "Start time: \(String(format: "%.3f", startTime)) s",
            "End time: \(String(format: "%.3f", endTime)) s",
            "Score: \(String(format: "%.2f", score))",
            "Evidence types: \(evidenceTypes.joined(separator: ", "))",
            "Detectors: \(detectorLabels.joined(separator: ", "))",
            "Click count: \(clickCount)",
            "Click bout count: \(clickBoutCount)",
            "Click train count: \(clickTrainCount)",
            "Whistle count: \(whistleCount)"
        ] + qualityFlags.map { "Quality flag: \($0)" }
    }

    var countSummary: String {
        [
            clickCount > 0 ? "\(clickCount) clicks" : nil,
            clickBoutCount > 0 ? "\(clickBoutCount) click bouts" : nil,
            clickTrainCount > 0 ? "\(clickTrainCount) click trains" : nil,
            whistleCount > 0 ? "\(whistleCount) whistles" : nil
        ]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private struct PAMGuardDetection {
    let id: String
    let table: String
    let utcMilliseconds: Double?
    let durationSeconds: Double?
    let lowFrequencyHz: Double?
    let highFrequencyHz: Double?
    let confidence: Double?
    let rawValues: [String: String]

    nonisolated var clipStartSeconds: Double? {
        Double(rawValues["begin_time_s"] ?? "")
    }

    nonisolated var clipDurationSeconds: Double? {
        Double(rawValues["duration_s"] ?? "")
    }

    nonisolated var formattedTime: String {
        guard let utcMilliseconds else { return PAMGuardPreview.unknownTime }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: utcMilliseconds / 1000.0))
    }
}

private struct PAMGuardBinaryHeader {
    let fileStartUTCMilliseconds: Double?
    let moduleType: String?
    let moduleName: String?
    let streamName: String?
}

nonisolated private func sortedUnique(_ values: [Int]) -> [Int] {
    Array(Set(values)).sorted()
}

nonisolated private func sortedUniqueStrings(_ values: [String]) -> [String] {
    Array(Set(values)).sorted()
}
