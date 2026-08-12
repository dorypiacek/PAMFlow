//
//  TopBar.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import SwiftUI

/// Shared application top bar with navigation, user identity, and settings.
struct TopBarView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @State private var isShowingSettings = false

    var backAction: (() -> Void)?

    var body: some View {
        HStack {
            HStack(spacing: Spacing.small) {
                if appCoordinator.canGoBack {
                    Button {
                        if let backAction {
                            backAction()
                        } else {
                            appCoordinator.goBack()
                        }
                    } label: {
                        Image(systemName: Icons.back)
                    }
                    .buttonStyle(.topBarIconAction)
                    .help(CommonStrings.back)
                }

                if appCoordinator.canGoHome {
                    Button {
                        appCoordinator.goHome()
                    } label: {
                        Image(systemName: Icons.home)
                    }
                    .buttonStyle(.topBarIconAction)
                    .help(CommonStrings.home)
                }
            }

            Spacer()

            Button {
                isShowingSettings = true
            } label: {
                HStack(spacing: Spacing.small) {
                Text("\(CommonStrings.loggedInPrefix) \(appCoordinator.userProfile?.name ?? CommonStrings.unknownUser)")
                    .foregroundStyle(.secondary)

                    Image(systemName: Icons.settings)
                        .frame(
                            width: Metrics.Layout.auditControlHeight,
                            height: Metrics.Layout.auditControlHeight
                        )
                }
                .padding(.leading, Spacing.medium)
            }
            .buttonStyle(.prominentSecondaryAction)
            .buttonBorderShape(.capsule)
            .help(CommonStrings.settingsButton)
        }
        .padding(.horizontal, Spacing.large)
        .padding(.top, Spacing.large)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
    }
}

private typealias CommonStrings = Strings.Common
