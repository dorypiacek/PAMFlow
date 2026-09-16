//
//  LoadingCardView.swift
//  PAMFlow
//
//  Created by Dory on 07/07/2026.
//

import SwiftUI
import Core

public struct LoadingCardView<Actions: View>: View {
    public let title: String
    public let subtitle: String
    public let message: String
    public let progress: Double?
    public let detail: String?
    public let errorMessage: String?
    @ViewBuilder let actions: () -> Actions

    public init(
        title: String,
        subtitle: String,
        message: String,
        progress: Double? = nil,
        detail: String? = nil,
        errorMessage: String? = nil,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.progress = progress
        self.detail = detail
        self.errorMessage = errorMessage
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: Spacing.large) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: Spacing.small) {
                Text(title)
                    .font(Fonts.screenTitle)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Metrics.Layout.readableTextWidth)
            }

            VStack(spacing: Spacing.small) {
                if let progress {
                    ProgressView(value: progress)
                        .frame(maxWidth: .infinity)
                }

                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Metrics.Layout.readableTextWidth)

                if let detail {
                    Text(detail)
                        .font(Fonts.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: Metrics.Layout.readableTextWidth)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(AppColors.error)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Metrics.Layout.readableTextWidth)
            }

            actions()
        }
        .padding(Spacing.xxLarge)
        .frame(maxWidth: Metrics.Layout.loadingCardWidth)
        .glassySurface()
        .frame(maxWidth: .infinity)
    }
}
