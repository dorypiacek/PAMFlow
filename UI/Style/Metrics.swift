//
//  Metrics.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import Foundation
import Core

/// Shared spacing scale for PAMFlow layouts.
public enum Spacing {
    public static let xSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let xLarge: CGFloat = 32
    public static let xxLarge: CGFloat = 48
}

/// Shared sizing and opacity constants used by SwiftUI views.
///
/// Views should add values here instead of hardcoding layout metrics inline.
public enum Metrics {
    public enum Layout {
        public static let topBarHeight: CGFloat = 52
        public static let compactContentWidth: CGFloat = 560
        public static let settingsWidth: CGFloat = 520
        public static let readableTextWidth: CGFloat = 640
        public static let regularContentWidth: CGFloat = 860
        public static let wideContentWidth: CGFloat = 1_400
        public static let loadingCardWidth: CGFloat = 760
        public static let loadingProgressWidth: CGFloat = 420
        public static let dataTypeButtonMinHeight: CGFloat = 220
        public static let dataTypeIconSize: CGFloat = 44
        public static let overviewModuleIconSize: CGFloat = 72
        public static let projectCardModuleIconSize: CGFloat = 56
        public static let projectSelectionCardHeight: CGFloat = 168
        public static let evidencePanelWidth: CGFloat = 260
        public static let auditOverviewMetricMinWidth: CGFloat = 260
        public static let highlightMetricMinWidth: CGFloat = 180
        public static let auditOverviewRowWidth: CGFloat = 420
        public static let auditOverviewCardHeight: CGFloat = 112
        public static let auditControlHeight: CGFloat = 24
        public static let buttonHeight: CGFloat = 32
        public static let textFieldHeight: CGFloat = 38
        public static let textFieldCornerRadius: CGFloat = 12
        public static let focusedBorderWidth: CGFloat = 2
        public static let actionButtonHeight: CGFloat = 40
        public static let decisionButtonMinWidth: CGFloat = 124
        public static let auditActionButtonMinWidth: CGFloat = 168
        public static let modalCloseButtonSize: CGFloat = 28
        public static let iconButtonSize: CGFloat = 32
        public static let chartAxisLeadingInset: CGFloat = 38
        public static let chartTrailingInset: CGFloat = 10
        public static let chartTopInset: CGFloat = 24
        public static let chartBottomInset: CGFloat = 34
        public static let chartMinimumHeight: CGFloat = 180
        public static let pickerWidth: CGFloat = 380
        public static let reasonSheetWidth: CGFloat = 520
        public static let speciesSearchFieldHeight: CGFloat = 22
        public static let speciesSearchVisibleRows = 5
        public static let searchDropdownVisibleRows = 5
        public static let searchDropdownRowHeight: CGFloat = 38
        public static let speciesSearchPopoverWidth: CGFloat = 720
        public static let speciesTaxonomyLabelWidth: CGFloat = 72
        public static let speciesTrackColumnWidth: CGFloat = 82
        public static let speciesConfidenceColumnWidth: CGFloat = 96
        public static let speciesActionColumnWidth: CGFloat = 44
        public static let circularToolbarButtonSize: CGFloat = 36
        public static let glassCornerRadius: CGFloat = 14
        public static let toolbarCapsuleCornerRadius: CGFloat = 24
        public static let rowCornerRadius: CGFloat = 8
        public static let scrubberTrackHeight: CGFloat = 6
        public static let scrubberThumbSize: CGFloat = 16
        public static let hairline: CGFloat = 1
    }

    public enum Opacity {
        public static let subtleStroke = 0.22
        public static let hoverHighlight = 0.18
    }

    public enum Cache {
        public static let previewLimit = 3
        public static let projectSelectionPreheatLimit = 3
        public static let manualAuditPrewarmCount = 1
    }
}
