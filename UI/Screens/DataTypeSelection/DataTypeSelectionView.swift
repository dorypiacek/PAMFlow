//
//  DataTypeSelectionView.swift
//  PAMFlow
//
//  Created by Dory on 18/06/2026.
//

import SwiftUI

/// Lets the user choose which workflow module a new project should use.
///
/// This screen is intentionally before project creation so folder layout,
/// scanning, preview rendering, and review steps can branch by module without
/// duplicating the setup flow.
struct DataTypeSelectionView: View {
    @Environment(AppCoordinator.self) private var appCoordinator

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            VStack(alignment: .center, spacing: Spacing.xLarge) {
                Text(Strings.DataTypeSelection.title)
                    .font(Fonts.screenTitle)
                    .multilineTextAlignment(.center)

                HStack(spacing: Spacing.large) {
                    ForEach(appCoordinator.moduleCatalog.details, id: \.id) { module in
                        DataTypeButton(module: module) {
                            appCoordinator.openModule(moduleID: module.id)
                        }
                    }
                }
                .frame(maxWidth: Metrics.Layout.regularContentWidth)
            }
            .frame(maxWidth: Metrics.Layout.regularContentWidth, alignment: .center)
            .padding(Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            Spacer()
        }
        .background(AppColors.background)
    }
}

/// Large module-selection button used by `DataTypeSelectionView`.
private struct DataTypeButton: View {
    let module: ModuleDetails
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.medium) {
                Image(systemName: module.iconName)
                    .font(.system(size: Metrics.Layout.dataTypeIconSize, weight: .semibold))

                Text(module.name)
                    .font(Fonts.subtitle.bold())
                    .multilineTextAlignment(.center)

                Text(module.subtitle)
                    .font(Fonts.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.Layout.dataTypeButtonMinHeight)
            .padding(Spacing.large)
            .glassySurface()
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.Layout.glassCornerRadius)
                    .stroke(
                        isHovering ? AppColors.accent.opacity(0.65) : Color.clear,
                        lineWidth: 1.5
                    )
            }
            .scaleEffect(isHovering ? 1.015 : 1)
            .shadow(color: isHovering ? AppColors.accent.opacity(0.22) : .clear, radius: 18, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: Metrics.Layout.glassCornerRadius))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.Layout.glassCornerRadius))
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}
