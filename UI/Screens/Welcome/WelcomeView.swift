//
//  WelcomeView.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import SwiftUI

/// First-run setup screen for the user name.
struct WelcomeView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @State private var name = ""

    var body: some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: "waveform")
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
            name = appCoordinator.userProfile?.name ?? ""
        }
    }

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        appCoordinator.saveUserName(name)
    }
}
