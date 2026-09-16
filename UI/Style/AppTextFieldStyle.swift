//
//  AppTextFieldStyle.swift
//  PAMFlow
//
//  Created by Dory on 04/08/2026.
//

import SwiftUI
import Core

/// Shared text field treatment that matches PAMFlow's translucent glass controls.
public struct AppTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    public var verticalPadding: CGFloat = 0

    public func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .focused($isFocused)
            .tint(AppColors.accent)
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: Metrics.Layout.textFieldHeight)
            .background {
                RoundedRectangle(cornerRadius: Metrics.Layout.textFieldCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(isFocused ? 0.22 : 0.16))
                    .background {
                        RoundedRectangle(cornerRadius: Metrics.Layout.textFieldCornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.Layout.textFieldCornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Metrics.Layout.textFieldCornerRadius, style: .continuous)
                    .stroke(
                        AppColors.accent.opacity(isFocused ? 0.85 : 0.3),
                        lineWidth: isFocused ? Metrics.Layout.focusedBorderWidth : Metrics.Layout.hairline
                    )
            }
    }
}

extension TextFieldStyle where Self == AppTextFieldStyle {
    /// Glassy app-native style for text entry controls.
    public static var appGlass: AppTextFieldStyle {
        AppTextFieldStyle()
    }

    /// Taller glassy style for multiline controls that need breathing room.
    public static var appGlassMultiline: AppTextFieldStyle {
        AppTextFieldStyle(verticalPadding: Spacing.small)
    }
}
