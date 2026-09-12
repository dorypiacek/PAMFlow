//
//  PAMFlowApp.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import SwiftUI
import SwiftData

/// PAMFlow macOS app entry point.
@main
struct PAMFlowApp: App {
    @State private var appCoordinator = AppCoordinator(
        userProfileStore: UserProfileStore(),
        appThemeStore: AppThemeStore(),
        dependencies: Dependencies(
            projectFileService: ProjectFileService(),
            projectScanService: ProjectScanService(),
            audioPreviewCacheService: AudioPreviewCacheService(),
            sharkTrackService: SharkTrackService(),
            pamGuardPreparationService: PAMGuardPreparationService(),
            pamGuardDetectionProcessingService: PAMGuardDetectionProcessingService(),
            fileSelectionService: FileSelectionService()
        ),
        moduleCatalog: IncludedModules.makeCatalog()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appCoordinator)
                .tint(AppColors.accent)
                .frame(minWidth: 900, minHeight: 520)
                .preferredColorScheme(appCoordinator.selectedTheme.colorScheme)
                .background(
                    ZStack {
                        Image("ocean")
                            .overlay(.ultraThinMaterial)
                    }
                )
        }
        .modelContainer(for: [
            Project.self,
            ManualAuditDecision.self
        ])
    }
}
