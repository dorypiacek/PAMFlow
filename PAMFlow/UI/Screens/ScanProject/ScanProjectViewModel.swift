//
//  ScanProjectViewModel.swift
//  PAMFlow
//
//  Created by Dory on 12/09/2026.
//

import Foundation
import Observation
import SwiftData

/// Defines the observable state and commands required by the project scanning screen.
@MainActor
protocol ScanProjectViewModelType: AnyObject {
    /// User-facing failure text from scanning or project removal.
    var errorMessage: String? { get set }
    /// Indicates whether a scan is currently running and prevents duplicate starts.
    var isScanning: Bool { get }
    /// Primary progress message shown while preparing, scanning, or finalizing.
    var scanMessage: String { get }
    /// Optional name of the file currently being scanned.
    var currentFileName: String? { get }
    /// Normalized progress value from `0...1`, or `nil` when progress is indeterminate.
    var progressFraction: Double? { get }
    /// Controls the destructive cancel confirmation.
    var showsCancelWarning: Bool { get set }

    /// Starts scanning the selected project and advances the workflow when scanning completes.
    func scanProject(modelContext: ModelContext, appCoordinator: AppCoordinating) async
    /// Deletes the partially created project and returns the user to the module setup flow.
    func removeProjectAndReturnToSetup(modelContext: ModelContext, appCoordinator: AppCoordinating)
}

/// View model that owns scan execution, progress reporting, and cancellation cleanup.
@Observable
@MainActor
final class ScanProjectViewModel: ScanProjectViewModelType {
    /// User-facing failure text from scanning or project removal.
    var errorMessage: String?
    /// Indicates whether a scan is currently running and prevents duplicate starts.
    var isScanning = false
    /// Primary progress message shown while preparing, scanning, or finalizing.
    var scanMessage = Strings.ScanProject.preparingMessage
    /// Optional name of the file currently being scanned.
    var currentFileName: String?
    /// Normalized progress value from `0...1`, or `nil` when progress is indeterminate.
    var progressFraction: Double?
    /// Controls the destructive cancel confirmation.
    var showsCancelWarning = false

    /// Identifier of the project being scanned.
    private let projectID: UUID
    /// File extensions the owning module wants Core to inventory.
    private let supportedFileExtensions: Set<String>
    /// Module-specific analyzer applied after Core has inventoried source files.
    private let scanAnalyzer: ProjectScanAnalyzing
    /// Prevents scan completion callbacks from mutating a project that the user discarded.
    private var didDiscardDuringScan = false

    /// Creates scan state for a persisted project and the owning module's scan behavior.
    init(
        projectID: UUID,
        supportedFileExtensions: Set<String>,
        scanAnalyzer: ProjectScanAnalyzing
    ) {
        self.projectID = projectID
        self.supportedFileExtensions = supportedFileExtensions
        self.scanAnalyzer = scanAnalyzer
    }

    /// Runs Core file discovery, applies module analysis, persists the summary, and opens the next workflow step.
    func scanProject(modelContext: ModelContext, appCoordinator: AppCoordinating) async {
        AppLog.info("ScanProjectView.task fired for projectID=\(projectID.uuidString)")
        guard !isScanning, let project = fetchProject(modelContext: modelContext) else {
            AppLog.info("ScanProjectView skipped scan. isScanning=\(isScanning), projectFound=\(fetchProject(modelContext: modelContext) != nil)")
            return
        }

        isScanning = true
        scanMessage = Strings.ScanProject.preparingMessage
        currentFileName = nil
        progressFraction = nil
        AppLog.info("ScanProjectView marking scan in progress for '\(project.name)'")
        do {
            project.workflowStatus = .scanInProgress
            project.scanStartedAt = .now
            project.lastOpenedAt = .now
            try modelContext.save()

            AppLog.info("ScanProjectView calling ProjectScanService.scanInventory")
            let inventory = try await appCoordinator.dependencies.projectScanService.scanInventory(
                project: project,
                supportedFileExtensions: supportedFileExtensions
            ) { progress in
                Task { @MainActor in
                    guard !self.didDiscardDuringScan else { return }
                    self.scanMessage = progress.message
                    self.currentFileName = progress.currentFile
                    self.progressFraction = progress.fractionCompleted
                }
            }
            let analyzedFiles = await analyzeFiles(inventory.files)
            let totalSizeBytes = analyzedFiles.reduce(0) { $0 + $1.sizeBytes }
            let warnings = scanAnalyzer.warnings(files: analyzedFiles, totalSizeBytes: totalSizeBytes)
            let summary = try appCoordinator.dependencies.projectScanService.makeSummary(
                inventory: inventory,
                analyzedFiles: analyzedFiles,
                warnings: warnings
            )
            guard !didDiscardDuringScan else {
                AppLog.info("ScanProjectView ignored scan completion because project was discarded")
                isScanning = false
                return
            }
            AppLog.info("ScanProjectView scan service returned successfully")

            scanMessage = Strings.ScanProject.finalizingMessage
            currentFileName = nil
            progressFraction = 1
            project.workflowStatus = .scanCompleted
            project.scanCompletedAt = .now
            project.lastOpenedAt = .now
            try project.storeScanSummary(summary)
            try modelContext.save()

            AppLog.info("ScanProjectView opening next workflow step")
            appCoordinator.goToNextStep(for: project)
        } catch {
            AppLog.info("ScanProjectView scan failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isScanning = false
        AppLog.info("ScanProjectView scanProject finished")
    }

    /// Removes the persisted project and project folder when the user cancels during scanning.
    func removeProjectAndReturnToSetup(modelContext: ModelContext, appCoordinator: AppCoordinating) {
        AppLog.info("ScanProjectView removing project and returning to setup")
        didDiscardDuringScan = true
        guard let project = fetchProject(modelContext: modelContext) else {
            appCoordinator.openProjectSelection()
            return
        }

        do {
            try appCoordinator.dependencies.projectFileService.deleteProjectFolder(for: project)
            modelContext.delete(project)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        appCoordinator.openModule(moduleID: ModuleID(rawValue: project.moduleID))
    }

    private func fetchProject(modelContext: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Applies the module analyzer to every inventoried file in scan order.
    private func analyzeFiles(_ files: [ProjectScanFileInfo]) async -> [ProjectScanFile] {
        var analyzedFiles: [ProjectScanFile] = []
        analyzedFiles.reserveCapacity(files.count)
        for file in files {
            analyzedFiles.append(await scanAnalyzer.analyzeFile(file))
        }
        return analyzedFiles
    }
}
