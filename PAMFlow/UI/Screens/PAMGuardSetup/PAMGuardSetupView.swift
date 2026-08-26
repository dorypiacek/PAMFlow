//
//  PAMGuardSetupView.swift
//  PAMFlow
//
//  Created by Dory on 17/06/2026.
//

import SwiftData
import SwiftUI

/// Prepares the PAMGuard project folder after PAM audio quality audit.
struct PAMGuardSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    let projectID: UUID
    let projectScanService: ProjectScanServicing
    let preparationService: PAMGuardPreparationServicing

    @State private var selectedTarget: PAMGuardPreparationService.DetectionTarget?
    @State private var result: PAMGuardPreparationService.Result?
    @State private var errorMessage: String?
    @State private var isPreparing = false
    @State private var showsPAMGuardHelp = false

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.large) {
                        Text(Strings.PAMGuardSetup.title)
                            .font(Fonts.screenTitle)

                        Text(Strings.PAMGuardSetup.subtitle)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: Metrics.Layout.readableTextWidth, alignment: .leading)

                        if let project = fetchProject() {
                            setupContent(project: project)
                        } else {
                            Text(Strings.Common.projectNotFound)
                                .foregroundStyle(AppColors.error)
                        }
                    }
                    .padding(Spacing.xxLarge)
                    .frame(maxWidth: Metrics.Layout.loadingCardWidth, alignment: .leading)
                    .glassySurface()
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .sheet(isPresented: $showsPAMGuardHelp) {
            PAMGuardRunHelpView(
                onShowPamguardFolder: pamguardFolderRevealAction()
            ) {
                showsPAMGuardHelp = false
            }
        }
        .task {
            restorePreparedResultIfNeeded()
        }
    }

    private func setupContent(project: Project) -> some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Picker(Strings.PAMGuardSetup.question, selection: $selectedTarget) {
                Text(Strings.PAMGuardSetup.selectDetectionTarget).tag(PAMGuardPreparationService.DetectionTarget?.none)
                ForEach(PAMGuardPreparationService.DetectionTarget.allCases) { target in
                    Text(target.title).tag(Optional(target))
                }
            }
            .frame(width: Metrics.Layout.pickerWidth, alignment: .leading)
            .onChange(of: selectedTarget) { _, target in
                guard let target else { return }
                prepare(project: project, target: target)
            }

            if isPreparing {
                HStack(spacing: Spacing.small) {
                    ProgressView()
                    Text(Strings.PAMGuardSetup.preparing)
                        .foregroundStyle(.secondary)
                }
            }

            if let result {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text(Strings.PAMGuardSetup.prepared)
                        .font(Fonts.subtitle)

                    Text(String(format: Strings.PAMGuardSetup.selectedInputCountFormat, result.linkedInputCount))
                        .foregroundStyle(.secondary)

                    Text(Strings.PAMGuardSetup.instructions)
                        .foregroundStyle(.secondary)

                    HStack(spacing: Spacing.medium) {
                        Button(Strings.PAMGuardSetup.showInFinder) {
                            revealTemplateInFinder(result.templateURL, project: project)
                        }
                        .buttonStyle(.secondaryAction)

                        Button(Strings.PAMGuardSetup.helpButton) {
                            showsPAMGuardHelp = true
                        }
                        .buttonStyle(.secondaryAction)
                    }
                }
                .padding(Spacing.medium)
                .glassySurface()
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppColors.error)
                    .multilineTextAlignment(.leading)
            }

            HStack(spacing: Spacing.medium) {
                Button(Strings.PAMGuardSetup.backButton) {
                    appCoordinator.openManualAuditOverview(project)
                }
                .buttonStyle(.secondaryAction)

                Button(Strings.PAMGuardSetup.continueButton) {
                    project.workflowStatus = .processingProjectCreated
                    project.lastOpenedAt = .now
                    try? modelContext.save()
                    appCoordinator.openPAMGuardWaiting(project)
                }
                .buttonStyle(.primaryAction)
                .disabled(result == nil)
            }
        }
    }

    private func prepare(project: Project, target: PAMGuardPreparationService.DetectionTarget) {
        selectedTarget = target
        isPreparing = true
        errorMessage = nil
        result = nil

        do {
            let summary = try projectScanService.loadSummary(for: project)
            let preparedResult = try preparationService.prepare(
                project: project,
                scanSummary: summary,
                decisions: auditDecisions(for: project),
                target: target
            )
            project.workflowStatus = .pamguardSetupReady
            project.lastOpenedAt = .now
            try modelContext.save()
            result = preparedResult
        } catch {
            errorMessage = error.localizedDescription
        }

        isPreparing = false
    }

    private func revealTemplateInFinder(_ templateURL: URL, project: Project) {
        let projectRootURL = project.rootFolderURL
        let accessed = projectRootURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessed {
                projectRootURL?.stopAccessingSecurityScopedResource()
            }
        }

        FileSelectionService.revealInFinder(templateURL)
    }

    private func pamguardFolderRevealAction() -> (() -> Void)? {
        guard let project = fetchProject(),
              let preparedResult = result ?? restoredPreparedResult(for: project) else {
            return nil
        }

        return {
            let projectRootURL = project.rootFolderURL
            let accessed = projectRootURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if accessed {
                    projectRootURL?.stopAccessingSecurityScopedResource()
                }
            }

            FileSelectionService.revealInFinder(preparedResult.templateURL)
        }
    }

    private func restorePreparedResultIfNeeded() {
        guard result == nil,
              let project = fetchProject(),
              let restoredResult = restoredPreparedResult(for: project) else {
            return
        }

        result = restoredResult
    }

    private func restoredPreparedResult(for project: Project) -> PAMGuardPreparationService.Result? {
        guard let projectRootURL = project.rootFolderURL else {
            return nil
        }

        let accessed = projectRootURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                projectRootURL.stopAccessingSecurityScopedResource()
            }
        }

        let pamguardURL = projectRootURL.appendingPathComponent(ProjectFileNames.pamguardDirectory, isDirectory: true)
        let inputURL = pamguardURL.appendingPathComponent("input", isDirectory: true)
        guard let templateURL = firstTemplateURL(in: pamguardURL) else {
            return nil
        }

        let linkedInputCount = (try? FileManager.default.contentsOfDirectory(
            at: inputURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).count) ?? 0

        return PAMGuardPreparationService.Result(
            templateURL: templateURL,
            linkedInputCount: linkedInputCount
        )
    }

    private func firstTemplateURL(in pamguardURL: URL) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: pamguardURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return files
            .filter { $0.pathExtension.localizedCaseInsensitiveCompare("psfx") == .orderedSame }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    private func auditDecisions(for project: Project) -> [ManualAuditDecision] {
        let projectID = project.id
        let descriptor = FetchDescriptor<ManualAuditDecision>(
            predicate: #Predicate { decision in
                decision.projectID == projectID
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
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
