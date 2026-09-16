//
//  PAMProjectCompletionView.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Core
import SwiftUI
import UI

/// PAM completion screen wrapper around the shared project-completion UI.
struct PAMProjectCompletionView: View {
    private let projectID: UUID
    private let projectScanService: ProjectScanServicing

    /// Creates a PAM completion screen backed by the shared scan-summary service.
    init(projectID: UUID, projectScanService: ProjectScanServicing) {
        self.projectID = projectID
        self.projectScanService = projectScanService
    }

    var body: some View {
        ProjectCompletionView(
            viewModel: PAMProjectCompletionViewModel(
                projectID: projectID,
                projectScanService: projectScanService
            )
        )
    }
}
