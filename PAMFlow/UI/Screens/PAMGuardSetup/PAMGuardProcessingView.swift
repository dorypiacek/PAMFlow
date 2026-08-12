//
//  PAMGuardProcessingView.swift
//  PAMFlow
//
//  Created by Dory on 03/07/2026.
//

import SwiftData
import SwiftUI

/// Imports PAMGuard detections and prepares the detection-review package.
struct PAMGuardProcessingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID
    let projectScanService: ProjectScanServicing
    let processingService: PAMGuardDetectionProcessingServicing

    @State private var message = Strings.PAMGuardProcessing.starting
    @State private var progress: Double?
    @State private var errorMessage: String?
    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    LoadingCardView(
                        title: Strings.PAMGuardProcessing.title,
                        subtitle: Strings.PAMGuardProcessing.subtitle,
                        message: message,
                        progress: progress,
                        errorMessage: errorMessage
                    ) {
                        if errorMessage != nil {
                            if let project = fetchProject() {
                                Button(Strings.PAMGuardProcessing.retry) {
                                    start(project: project)
                                }
                                .buttonStyle(.primaryAction)
                            }
                        }
                    }
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task {
            guard !hasStarted, let project = fetchProject() else { return }
            hasStarted = true
            start(project: project)
        }
    }

    private func start(project: Project) {
        errorMessage = nil
        progress = nil
        message = Strings.PAMGuardProcessing.starting

        Task {
            do {
                let originalSummary = try projectScanService.loadSummary(for: project)
                let summary = try await processingService.process(project: project, originalSummary: originalSummary) { update in
                    Task { @MainActor in
                        message = update.message
                        progress = update.fractionCompleted
                    }
                }

                project.workflowStatus = .processingRunImported
                project.lastOpenedAt = .now
                try project.storeScanSummary(summary)
                try modelContext.save()
                appCoordinator.openManualAuditOverview(project)
            } catch {
                errorMessage = error.localizedDescription
                message = Strings.PAMGuardProcessing.failed
            }
        }
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
