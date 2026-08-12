//
//  AppTextFieldStyle.swift
//  PAMFlow
//
//  Created by Codex on 04/08/2026.
//

import SwiftUI

/// Shared text field treatment that matches PAMFlow's translucent glass controls.
struct AppTextFieldStyle: TextFieldStyle {
    @FocusState private var isFocused: Bool
    var verticalPadding: CGFloat = 0

    func _body(configuration: TextField<Self._Label>) -> some View {
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
    static var appGlass: AppTextFieldStyle {
        AppTextFieldStyle()
    }

    /// Taller glassy style for multiline controls that need breathing room.
    static var appGlassMultiline: AppTextFieldStyle {
        AppTextFieldStyle(verticalPadding: Spacing.small)
    }
}
