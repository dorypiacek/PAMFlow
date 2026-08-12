//
//  Metrics.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation

/// Shared spacing scale for PAMFlow layouts.
enum Spacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
    static let xxLarge: CGFloat = 48
}

/// Shared sizing and opacity constants used by SwiftUI views.
///
/// Views should add values here instead of hardcoding layout metrics inline.
enum Metrics {
    enum Layout {
        static let topBarHeight: CGFloat = 52
        static let compactContentWidth: CGFloat = 560
        static let settingsWidth: CGFloat = 520
        static let readableTextWidth: CGFloat = 640
        static let regularContentWidth: CGFloat = 860
        static let wideContentWidth: CGFloat = 1_400
        static let loadingCardWidth: CGFloat = 760
        static let loadingProgressWidth: CGFloat = 420
        static let dataTypeButtonMinHeight: CGFloat = 220
        static let dataTypeIconSize: CGFloat = 44
        static let overviewModuleIconSize: CGFloat = 72
        static let projectCardModuleIconSize: CGFloat = 56
        static let projectSelectionCardHeight: CGFloat = 168
        static let evidencePanelWidth: CGFloat = 260
        static let auditOverviewMetricMinWidth: CGFloat = 260
        static let highlightMetricMinWidth: CGFloat = 180
        static let auditOverviewRowWidth: CGFloat = 420
        static let auditOverviewCardHeight: CGFloat = 112
        static let auditControlHeight: CGFloat = 24
        static let buttonHeight: CGFloat = 32
        static let textFieldHeight: CGFloat = 38
        static let textFieldCornerRadius: CGFloat = 12
        static let focusedBorderWidth: CGFloat = 2
        static let actionButtonHeight: CGFloat = 40
        static let decisionButtonMinWidth: CGFloat = 124
        static let auditActionButtonMinWidth: CGFloat = 168
        static let modalCloseButtonSize: CGFloat = 28
        static let iconButtonSize: CGFloat = 32
        static let audioButtonIconSize: CGFloat = 18
        static let audioTransportButtonSize: CGFloat = 28
        static let audioTimeLabelWidth: CGFloat = 44
        static let chartAxisLeadingInset: CGFloat = 38
        static let chartTrailingInset: CGFloat = 10
        static let chartTopInset: CGFloat = 24
        static let chartBottomInset: CGFloat = 34
        static let chartMinimumHeight: CGFloat = 180
        static let pickerWidth: CGFloat = 380
        static let reasonSheetWidth: CGFloat = 520
        static let speciesSearchResultsHeight: CGFloat = 220
        static let speciesSearchFieldHeight: CGFloat = 22
        static let speciesTrackColumnWidth: CGFloat = 72
        static let speciesConfidenceColumnWidth: CGFloat = 72
        static let speciesActionColumnWidth: CGFloat = 44
        static let circularToolbarButtonSize: CGFloat = 36
        static let glassCornerRadius: CGFloat = 14
        static let toolbarCapsuleCornerRadius: CGFloat = 24
        static let rowCornerRadius: CGFloat = 8
        static let scrubberTrackHeight: CGFloat = 6
        static let scrubberThumbSize: CGFloat = 16
        static let hairline: CGFloat = 1
    }

    enum Opacity {
        static let subtleStroke = 0.22
        static let hoverHighlight = 0.18
    }

    enum Cache {
        static let previewLimit = 3
        static let projectSelectionPreheatLimit = 3
        static let manualAuditPrewarmCount = 1
    }
}
