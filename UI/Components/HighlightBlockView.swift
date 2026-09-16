//
//  HighlightBlockView.swift
//  PAMFlow
//
//  Created by Dory on 07/07/2026.
//

import SwiftUI
import Core

public struct HighlightMetric: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let value: String
    public let valueColor: Color

    public init(_ title: String, _ value: String, valueColor: Color = .primary) {
        self.title = title
        self.value = value
        self.valueColor = valueColor
    }
}

public struct HighlightBlockView: View {
    public let count: String
    public let title: String
    public let metrics: [HighlightMetric]

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    highlightTitle
                }

                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    highlightTitle
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Metrics.Layout.highlightMetricMinWidth), alignment: .leading)],
                alignment: .leading,
                spacing: Spacing.large
            ) {
                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(metric.title)
                            .font(Fonts.caption)
                            .foregroundStyle(.secondary)

                        Text(metric.value.isEmpty ? Strings.Common.unknown : metric.value)
                            .font(Fonts.subtitle.weight(.bold))
                            .foregroundStyle(metric.valueColor)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassySurface()
    }

    private var highlightTitle: some View {
        Group {
            Text(count)
                .font(Fonts.screenTitle.monospacedDigit())
                .monospacedDigit()

            Text(title)
                .font(Fonts.screenTitle)
                .lineLimit(2)
        }
    }
}
