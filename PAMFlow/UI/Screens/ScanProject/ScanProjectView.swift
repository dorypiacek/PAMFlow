//
//  ScanProjectView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftData
import SwiftUI

/// Runs the technical scan step and displays progress for the selected project.
struct ScanProjectView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID

    @State private var errorMessage: String?
    @State private var isScanning = false
    @State private var scanMessage = Strings.ScanProject.preparingMessage
    @State private var currentFileName: String?
    @State private var progressFraction: Double?
    @State private var showsCancelWarning = false
    @State private var didDiscardDuringScan = false

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    LoadingCardView(
                        title: Strings.ScanProject.title,
                        subtitle: Strings.ScanProject.subtitle,
                        message: scanMessage,
                        progress: progressFraction,
                        detail: currentFileName,
                        errorMessage: errorMessage
                    ) {
                        Button(Strings.ScanProject.backButton) {
                            showsCancelWarning = true
                        }
                        .buttonStyle(.secondaryAction)
                    }
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task {
            await scanProject()
        }
        .alert(
            Strings.ScanProject.cancelTitle,
            isPresented: $showsCancelWarning,
        ) {
            Button(Strings.ScanProject.cancelConfirmButton, role: .destructive) {
                removeProjectAndReturnToSetup()
            }

            Button(Strings.ScanProject.cancelDismissButton, role: .cancel) {}
        } message: {
            Text(Strings.ScanProject.cancelMessage)
        }
    }

    private func scanProject() async {
        AppLog.info("ScanProjectView.task fired for projectID=\(projectID.uuidString)")
        guard !isScanning, let project = fetchProject() else {
            AppLog.info("ScanProjectView skipped scan. isScanning=\(isScanning), projectFound=\(fetchProject() != nil)")
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

            AppLog.info("ScanProjectView calling ProjectScanService.scan")
            let summary = try await appCoordinator.dependencies.projectScanService.scan(project: project) { progress in
                Task { @MainActor in
                    guard !didDiscardDuringScan else { return }
                    scanMessage = progress.message
                    currentFileName = progress.currentFile
                    progressFraction = progress.fractionCompleted
                }
            }
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

            AppLog.info("ScanProjectView opening NewProjectOverview")
            appCoordinator.openNewProjectOverview(project)
        } catch {
            AppLog.info("ScanProjectView scan failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
        isScanning = false
        AppLog.info("ScanProjectView scanProject finished")
    }

    private func removeProjectAndReturnToSetup() {
        AppLog.info("ScanProjectView removing project and returning to setup")
        didDiscardDuringScan = true
        guard let project = fetchProject() else {
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

    private func fetchProject() -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { project in
                project.id == projectID
            }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
