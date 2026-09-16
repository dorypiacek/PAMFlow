//
//  TopBar.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import SwiftUI
import Core

/// Shared application top bar with navigation, user identity, and settings.
public struct TopBarView: View {
    @Environment(\.appCoordinator) private var appCoordinator

    private var coordinator: any AppCoordinating {
        guard let appCoordinator else {
            fatalError("App coordinator must be injected before rendering shared UI")
        }
        return appCoordinator
    }
    @State private var isShowingSettings = false

    public var backAction: (() -> Void)?

    public init(backAction: (() -> Void)? = nil) {
        self.backAction = backAction
    }

    public var body: some View {
        HStack {
            HStack(spacing: Spacing.small) {
                if coordinator.canGoBack {
                    Button {
                        if let backAction {
                            backAction()
                        } else {
                            coordinator.goBack()
                        }
                    } label: {
                        Image(systemName: Icons.back)
                    }
                    .buttonStyle(.topBarIconAction)
                    .help(CommonStrings.back)
                }

                if coordinator.canGoHome {
                    Button {
                        coordinator.goHome()
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
                Text("\(CommonStrings.loggedInPrefix) \(coordinator.userProfile?.name ?? CommonStrings.unknownUser)")
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
