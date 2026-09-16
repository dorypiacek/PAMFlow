//
//  WelcomeView.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import SwiftUI
import Core

/// First-run setup screen for the user name.
public struct WelcomeView: View {
    @Environment(\.appCoordinator) private var appCoordinator

    private var coordinator: any AppCoordinating {
        guard let appCoordinator else {
            fatalError("App coordinator must be injected before rendering shared UI")
        }
        return appCoordinator
    }
    @State private var name = ""

    public init() {}

    public var body: some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: Icons.app)
                .font(.system(size: 80, weight: .light))

            VStack(spacing: Spacing.small) {
                Text(Strings.Welcome.title)
                    .font(Fonts.screenTitle)

                Text(Strings.Welcome.subtitle)
                    .font(Fonts.subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            TextField(Strings.Welcome.namePlaceholder, text: $name)
                .textFieldStyle(.appGlass)
                .frame(width: 320)
                .onSubmit(save)

            Button(Strings.Welcome.continueButton) {
                save()
            }
            .buttonStyle(.primaryAction)
            .disabled(!canContinue)
        }
        .padding(Spacing.xxLarge)
        .frame(minWidth: 720, minHeight: 520)
        .background(AppColors.background)
        .onAppear {
            name = coordinator.userProfile?.name ?? ""
        }
    }

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        coordinator.saveUserName(name)
    }
}
