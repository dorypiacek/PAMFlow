//
//  AppButtonStyle.swift
//  PAMFlow
//
//  Created by Dory on 29/07/2026.
//

import SwiftUI
import Core

/// Defines the two shared capsule button treatments used across PAMFlow.
public struct AppButtonStyle: ButtonStyle {
    public enum Role {
        case primary
        case secondary
        case prominentSecondary
    }

    public let role: Role

    @Environment(\.isEnabled) private var isEnabled

    public init(role: Role) {
        self.role = role
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: Metrics.Layout.buttonHeight)
            .background(background(configuration: configuration))
            .overlay(border)
            .clipShape(Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundStyle: Color {
        switch role {
        case .primary:
            .white
        case .secondary, .prominentSecondary:
            .primary
        }
    }

    private func background(configuration: Configuration) -> some View {
        Capsule()
            .fill(backgroundColor(configuration: configuration))
            .background {
                Capsule()
                    .fill(.regularMaterial)
            }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        switch role {
        case .primary:
            AppColors.accent.opacity(configuration.isPressed ? 0.82 : 0.95)
        case .secondary, .prominentSecondary:
            Color.black.opacity(configuration.isPressed ? 0.24 : 0.16)
        }
    }

    @ViewBuilder
    private var border: some View {
        switch role {
        case .primary:
            Capsule().stroke(AppColors.accent.opacity(0.55), lineWidth: Metrics.Layout.hairline)
        case .secondary, .prominentSecondary:
            Capsule().stroke(AppColors.accent.opacity(0.48), lineWidth: Metrics.Layout.hairline)
        }
    }
}

/// Shared circular treatment for icon-only buttons.
public struct IconButtonStyle: ButtonStyle {
    public let size: CGFloat

    @Environment(\.isEnabled) private var isEnabled

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.4, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(Color.black.opacity(configuration.isPressed ? 0.24 : 0.16))
                    .background {
                        Circle().fill(.regularMaterial)
                    }
                    .clipShape(Circle())
            }
            .overlay {
                Circle().stroke(AppColors.accent.opacity(0.2), lineWidth: Metrics.Layout.hairline)
            }
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    /// Filled, tint-colored style for primary actions and confirmations.
    public static var primaryAction: AppButtonStyle {
        AppButtonStyle(role: .primary)
    }

    /// Neutral glass style for secondary actions.
    public static var secondaryAction: AppButtonStyle {
        AppButtonStyle(role: .secondary)
    }

    /// Secondary style with a tint-colored border for selected or emphasized secondary actions.
    public static var prominentSecondaryAction: AppButtonStyle {
        AppButtonStyle(role: .prominentSecondary)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    /// Circular style for icon-only controls.
    public static var iconAction: IconButtonStyle {
        IconButtonStyle(size: Metrics.Layout.iconButtonSize)
    }

    /// Larger circular style for top-bar icon controls.
    public static var topBarIconAction: IconButtonStyle {
        IconButtonStyle(size: Metrics.Layout.buttonHeight)
    }
}
