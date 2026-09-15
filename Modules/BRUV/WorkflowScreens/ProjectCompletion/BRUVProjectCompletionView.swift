//
//  BRUVProjectCompletionView.swift
//  PAMFlow
//
//  Created by Dory on 14/09/2026.
//

import Core
import SwiftUI
import UI

/// BRUV/RUV completion screen wrapper around the shared project-completion UI.
struct BRUVProjectCompletionView: View {
    private let projectID: UUID
    private let projectScanService: ProjectScanServicing

    /// Creates a visual-workflow completion screen backed by the shared scan-summary service.
    init(projectID: UUID, projectScanService: ProjectScanServicing) {
        self.projectID = projectID
        self.projectScanService = projectScanService
    }

    var body: some View {
        ProjectCompletionView(
            viewModel: BRUVProjectCompletionViewModel(
                projectID: projectID,
                projectScanService: projectScanService
            )
        )
    }
}
