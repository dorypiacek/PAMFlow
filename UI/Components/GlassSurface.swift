//
//  GlassSurface.swift
//  PAMFlow
//
//  Created by Dory on 24/06/2026.
//

import SwiftUI
import Core

/// Applies PAMFlow's shared translucent surface treatment to grouped content.
private struct GlassSurfaceModifier: ViewModifier {
    public let cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .background {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.regularMaterial)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppColors.accent.opacity(0.35), lineWidth: 1)
            }
    }
}

extension View {
    /// Places content on a native Liquid Glass surface with shared geometry.
    public func glassySurface(
        cornerRadius: CGFloat = Metrics.Layout.glassCornerRadius
    ) -> some View {
        modifier(GlassSurfaceModifier(cornerRadius: cornerRadius))
    }
}
