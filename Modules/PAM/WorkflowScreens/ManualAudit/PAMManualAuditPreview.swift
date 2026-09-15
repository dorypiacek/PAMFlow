//
//  PAMManualAuditPreview.swift
//  PAMFlow
//
//  Created by Dory on 15/09/2026.
//

import Core
import SwiftUI
import UI

/// PAM-owned preview content for manual audit and PAMGuard detection review.
///
/// This view keeps all audio rendering, playback, and scrubber behavior inside
/// the PAM module while the shared manual-audit screen owns only workflow chrome
/// and decision controls.
struct PAMManualAuditPreview: View {
    @StateObject private var playbackService = AudioPlaybackService()

    let viewModel: PAMManualAuditViewModel
    let project: Project
    let file: ProjectScanFile

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            previewBody

            audioControls
        }
        .frame(maxHeight: .infinity)
        .onDisappear {
            playbackService.stop()
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        if viewModel.isLoadingPreview {
            VStack(spacing: Spacing.small) {
                ProgressView()
                Text(PAMStrings.Preview.loading)
                    .font(Fonts.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else if let preview = viewModel.preview {
            previewImages(preview)
        } else {
            Text(viewModel.errorMessage ?? PAMStrings.Preview.unavailable)
                .foregroundStyle(AppColors.error)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private func previewImages(_ preview: AudioPreview) -> some View {
        GeometryReader { proxy in
            let availableHeight = max(1, proxy.size.height - Spacing.small)
            let plotContainerHeight = max(1, availableHeight / 2)

            VStack(spacing: Spacing.small) {
                ChartWithPlayhead(durationSeconds: preview.durationSeconds, playbackService: playbackService) {
                    WaveformView(peaks: preview.waveformPeaks, durationSeconds: preview.durationSeconds)
                }
                .frame(height: plotContainerHeight)

                ChartWithPlayhead(durationSeconds: preview.durationSeconds, playbackService: playbackService) {
                    SpectrogramView(
                        bins: preview.spectrogramBins,
                        durationSeconds: preview.durationSeconds,
                        maxFrequencyHz: preview.spectrogramMaxFrequencyHz
                    )
                }
                .frame(height: plotContainerHeight)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var audioControls: some View {
        GeometryReader { proxy in
            let rowHeight = Metrics.Layout.auditControlHeight
            let buttonSize = PAMPreviewMetrics.transportButtonSize
            let timeLabelHeight = Metrics.Layout.auditControlHeight * 0.4
            let timeLabelSpacing: CGFloat = 1
            let timelineHeight = rowHeight + timeLabelSpacing + timeLabelHeight
            let controlHeight = max(buttonSize, timelineHeight)
            let buttonTopOffset = (rowHeight - buttonSize) / 2
            let plot = chartPlotRect(proxy.size)
            let controlSpacing = max(0, plot.minX - buttonSize)

            HStack(alignment: .top, spacing: controlSpacing) {
                Button {
                    play()
                } label: {
                    Image(systemName: playbackService.isPlaying ? Icons.pause : Icons.play)
                        .font(.system(size: PAMPreviewMetrics.buttonIconSize * 0.72, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(AppColors.accent, in: Circle())
                }
                .help(playbackService.isPlaying ? PAMStrings.Preview.pauseHelp : PAMStrings.Preview.playHelp)
                .buttonStyle(.plain)
                .disabled(viewModel.playbackURL(project: project, file: file) == nil)
                .frame(width: buttonSize, height: buttonSize, alignment: .center)
                .offset(y: buttonTopOffset)

                TimelineView(.animation) { timeline in
                    let playbackPosition = playbackService.displayTime(at: timeline.date)

                    VStack(alignment: .leading, spacing: timeLabelSpacing) {
                        AudioScrubber(
                            currentTime: playbackPosition,
                            duration: playbackService.duration,
                            onDragStart: playbackService.pause,
                            onSeek: playbackService.seek(to:)
                        )
                        .frame(width: plot.width, height: rowHeight, alignment: .center)

                        Text(remainingPlaybackTime(playbackPosition, duration: playbackService.duration))
                            .font(Fonts.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: plot.width, height: timeLabelHeight, alignment: .trailing)
                    }
                    .frame(width: plot.width, height: timelineHeight, alignment: .center)
                }
                .frame(width: plot.width, height: timelineHeight, alignment: .center)
            }
            .frame(width: proxy.size.width, height: controlHeight, alignment: .leading)
        }
        .frame(
            height: max(
                PAMPreviewMetrics.transportButtonSize,
                Metrics.Layout.auditControlHeight + 1 + Metrics.Layout.auditControlHeight * 0.75
            )
        )
        .onAppear {
            preparePlayback()
        }
        .onChange(of: file.relativePath) {
            playbackService.stop()
            preparePlayback()
        }
    }

    private func play() {
        guard let url = viewModel.playbackURL(project: project, file: file),
              let inputFolderURL = project.inputFolderURL else { return }

        do {
            try playbackService.togglePlayback(
                url: url,
                securityScopedURL: inputFolderURL,
                clipStartSeconds: viewModel.playbackStartSeconds(project: project, file: file),
                clipDurationSeconds: viewModel.playbackDurationSeconds(project: project, file: file)
            )
            viewModel.errorMessage = nil
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func preparePlayback() {
        guard let playbackURL = viewModel.playbackURL(project: project, file: file),
              let inputFolderURL = project.inputFolderURL else {
            return
        }

        playbackService.prepareIfNeeded(
            url: playbackURL,
            securityScopedURL: inputFolderURL,
            clipStartSeconds: viewModel.playbackStartSeconds(project: project, file: file),
            clipDurationSeconds: viewModel.playbackDurationSeconds(project: project, file: file)
        )
    }

    private func formatPlaybackTime(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }

        let totalSeconds = Int(seconds.rounded())
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
    }

    private func remainingPlaybackTime(_ currentTime: Double, duration: Double) -> String {
        "-\(formatPlaybackTime(max(duration - currentTime, 0)))"
    }
}

private enum PAMPreviewMetrics {
    static let buttonIconSize: CGFloat = 18
    static let transportButtonSize: CGFloat = 28
}

private struct WaveformView: View {
    let peaks: [WaveformPeak]
    let durationSeconds: Double
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            guard peaks.count > 1 else { return }

            let plot = chartPlotRect(size)
            let midY = plot.midY
            let xStep = plot.width / CGFloat(max(1, peaks.count - 1))
            let scale = plot.height / 2

            drawAxes(context: context, plot: plot)

            var upper = Path()
            var lowerPoints: [CGPoint] = []
            for index in peaks.indices {
                let x = plot.minX + CGFloat(index) * xStep
                let minY = midY - CGFloat(peaks[index].minimum) * scale
                let maxY = midY - CGFloat(peaks[index].maximum) * scale
                let upperPoint = CGPoint(x: x, y: maxY)
                let lowerPoint = CGPoint(x: x, y: minY)
                if index == peaks.startIndex {
                    upper.move(to: upperPoint)
                } else {
                    upper.addLine(to: upperPoint)
                }
                lowerPoints.append(lowerPoint)
            }

            for point in lowerPoints.reversed() {
                upper.addLine(to: point)
            }
            upper.closeSubpath()

            context.fill(upper, with: .color(Color(red: 0.12, green: 0.47, blue: 0.71)))
            context.stroke(upper, with: .color(Color(red: 0.12, green: 0.47, blue: 0.71)), lineWidth: 1)
        }
    }

    private func drawAxes(context: GraphicsContext, plot: CGRect) {
        var background = Path()
        background.addRect(plot)
        context.fill(background, with: .color(waveformPlotBackground(colorScheme)))

        for value in [-1.0, -0.5, 0, 0.5, 1.0] {
            let y = plot.midY - CGFloat(value) * plot.height / 2
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(chartGridColor(colorScheme).opacity(value == 0 ? 0.22 : 0.10)), lineWidth: 1)
        }

        var border = Path()
        border.addRect(plot)
        context.stroke(border, with: .color(chartAxisColor(colorScheme)), lineWidth: 1)

        drawText(context, PAMStrings.Preview.amplitudeAxis, CGPoint(x: plot.minX, y: plot.minY - 22), color: chartLabelColor(colorScheme))
        drawText(context, PAMStrings.Preview.timeAxis, CGPoint(x: plot.midX - 24, y: plot.maxY + 22), color: chartLabelColor(colorScheme))
        drawText(context, "1", CGPoint(x: 0, y: plot.minY - 6), color: chartLabelColor(colorScheme))
        drawText(context, "0", CGPoint(x: 0, y: plot.midY - 6), color: chartLabelColor(colorScheme))
        drawText(context, "-1", CGPoint(x: 0, y: plot.maxY - 10), color: chartLabelColor(colorScheme))

        for tick in timeTicks(duration: durationSeconds) {
            let x = plot.minX + plot.width * CGFloat(tick / max(durationSeconds, 0.01))
            drawText(context, "\(Int(tick))", CGPoint(x: x - 4, y: plot.maxY + 6), color: chartLabelColor(colorScheme))
        }
    }
}

private struct SpectrogramView: View {
    let bins: [[Float]]
    let durationSeconds: Double
    let maxFrequencyHz: Double
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            guard let firstColumn = bins.first, !firstColumn.isEmpty else { return }

            let plot = chartPlotRect(size)
            let maxFrequency = max(maxFrequencyHz, 1)
            var background = Path()
            background.addRect(plot)
            context.fill(background, with: .color(spectrogramPlotBackground))

            var plotContext = context
            plotContext.clip(to: Path(plot))
            let rasterScale = max(displayScale, 1)
            let sampleColumns = max(1, min(Int((plot.width * rasterScale).rounded(.up)), bins.count, 900))
            let sampleRows = max(1, min(Int((plot.height * rasterScale).rounded(.up)), firstColumn.count, 256))
            let cellWidth = plot.width / CGFloat(sampleColumns)
            let cellHeight = plot.height / CGFloat(sampleRows)

            for xIndex in 0..<sampleColumns {
                let x = plot.minX + CGFloat(xIndex) * cellWidth
                for yIndex in 0..<sampleRows {
                    let value = rasterValue(xIndex: xIndex, yIndex: yIndex, rasterColumns: sampleColumns, rasterRows: sampleRows)
                    let y = plot.maxY - CGFloat(yIndex + 1) * cellHeight
                    let rect = CGRect(x: x, y: y, width: cellWidth + 0.75, height: cellHeight + 0.75).intersection(plot)
                    guard !rect.isNull, rect.width > 0, rect.height > 0 else { continue }
                    plotContext.fill(Path(rect), with: .color(color(for: value)))
                }
            }

            drawAxes(context: context, plot: plot, maxFrequency: maxFrequency)
        }
    }

    private func rasterValue(xIndex: Int, yIndex: Int, rasterColumns: Int, rasterRows: Int) -> Double {
        guard let firstColumn = bins.first, !bins.isEmpty, !firstColumn.isEmpty else { return 0 }
        let columnStart = Double(xIndex) / Double(max(rasterColumns, 1)) * Double(bins.count)
        let columnEnd = Double(xIndex + 1) / Double(max(rasterColumns, 1)) * Double(bins.count)
        let rowStart = Double(yIndex) / Double(max(rasterRows, 1)) * Double(firstColumn.count)
        let rowEnd = Double(yIndex + 1) / Double(max(rasterRows, 1)) * Double(firstColumn.count)

        if columnEnd - columnStart <= 1, rowEnd - rowStart <= 1 {
            let time = durationSeconds * (Double(xIndex) + 0.5) / Double(max(rasterColumns, 1))
            let frequency = maxFrequencyHz * (Double(yIndex) + 0.5) / Double(max(rasterRows, 1))
            return interpolatedValue(time: time, frequency: frequency)
        }

        let columnLower = min(bins.count - 1, max(0, Int(floor(columnStart))))
        let columnUpper = min(bins.count - 1, max(columnLower, Int(ceil(columnEnd)) - 1))
        let rowLower = min(firstColumn.count - 1, max(0, Int(floor(rowStart))))
        let rowUpper = min(firstColumn.count - 1, max(rowLower, Int(ceil(rowEnd)) - 1))
        var peak = 0.0

        for column in columnLower...columnUpper {
            var sum = 0.0
            var count = 0
            for row in rowLower...rowUpper {
                sum += valueAt(column: column, row: row)
                count += 1
            }
            if count > 0 {
                peak = max(peak, sum / Double(count))
            }
        }
        return peak
    }

    private func interpolatedValue(time: Double, frequency: Double) -> Double {
        guard let firstColumn = bins.first, !bins.isEmpty, !firstColumn.isEmpty else { return 0 }
        let maxColumn = Double(bins.count - 1)
        let maxRow = Double(firstColumn.count - 1)
        let displayedMaxFrequency = max(maxFrequencyHz, 1)
        let columnPosition = min(max(time / max(durationSeconds, 0.01) * maxColumn, 0), maxColumn)
        let rowPosition = min(max(frequency / displayedMaxFrequency * maxRow, 0), maxRow)
        let column0 = Int(floor(columnPosition))
        let row0 = Int(floor(rowPosition))
        let column1 = min(column0 + 1, bins.count - 1)
        let row1 = min(row0 + 1, firstColumn.count - 1)
        let columnFraction = columnPosition - Double(column0)
        let rowFraction = rowPosition - Double(row0)
        let value00 = valueAt(column: column0, row: row0)
        let value10 = valueAt(column: column1, row: row0)
        let value01 = valueAt(column: column0, row: row1)
        let value11 = valueAt(column: column1, row: row1)
        let lower = value00 + (value10 - value00) * columnFraction
        let upper = value01 + (value11 - value01) * columnFraction
        return lower + (upper - lower) * rowFraction
    }

    private func valueAt(column: Int, row: Int) -> Double {
        guard bins.indices.contains(column), bins[column].indices.contains(row) else { return 0 }
        return Double(bins[column][row])
    }

    private func color(for value: Double) -> Color {
        let stops: [(Double, Double, Double, Double)] = [
            (0.04, 0.02, 0.12, 1.00),
            (0.16, 0.05, 0.34, 1.00),
            (0.46, 0.08, 0.55, 1.00),
            (0.86, 0.24, 0.45, 1.00),
            (1.00, 0.55, 0.22, 1.00),
            (1.00, 0.92, 0.60, 1.00)
        ]
        let clamped = pow(min(1, max(0, value)), 0.55)
        let scaled = clamped * Double(stops.count - 1)
        let lower = min(Int(scaled), stops.count - 2)
        let fraction = scaled - Double(lower)
        let a = stops[lower]
        let b = stops[lower + 1]
        return Color(red: a.0 + (b.0 - a.0) * fraction, green: a.1 + (b.1 - a.1) * fraction, blue: a.2 + (b.2 - a.2) * fraction, opacity: a.3 + (b.3 - a.3) * fraction)
    }

    private func drawAxes(context: GraphicsContext, plot: CGRect, maxFrequency: Double) {
        drawText(context, PAMStrings.Preview.frequencyAxis, CGPoint(x: plot.minX, y: plot.minY - 22), color: chartLabelColor(colorScheme))
        drawText(context, PAMStrings.Preview.timeAxis, CGPoint(x: plot.midX - 24, y: plot.maxY + 22), color: chartLabelColor(colorScheme))
        var border = Path()
        border.addRect(plot)
        context.stroke(border, with: .color(chartAxisColor(colorScheme)), lineWidth: 1)

        for tick in frequencyTicks(maxFrequency: maxFrequency) {
            let y = plot.maxY - plot.height * CGFloat(tick / max(maxFrequency, 1))
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
            drawText(context, frequencyLabel(tick), CGPoint(x: 0, y: y - 7), color: chartLabelColor(colorScheme))
        }

        for tick in timeTicks(duration: durationSeconds) {
            let x = plot.minX + plot.width * CGFloat(tick / max(durationSeconds, 0.01))
            drawText(context, "\(Int(tick))", CGPoint(x: x - 4, y: plot.maxY + 6), color: chartLabelColor(colorScheme))
        }
    }
}

private struct ChartWithPlayhead<Content: View>: View {
    let durationSeconds: Double
    @ObservedObject var playbackService: AudioPlaybackService
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            content()
            TimelineView(.animation) { timeline in
                PlayheadOverlay(durationSeconds: durationSeconds, playbackPosition: playbackService.displayTime(at: timeline.date))
            }
        }
    }
}

private struct PlayheadOverlay: View {
    let durationSeconds: Double
    let playbackPosition: Double

    var body: some View {
        GeometryReader { proxy in
            let plot = chartPlotRect(proxy.size)
            let progress = durationSeconds > 0 ? min(max(playbackPosition / durationSeconds, 0), 1) : 0
            let x = plot.minX + plot.width * CGFloat(progress)

            Rectangle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 1, height: plot.height)
                .position(x: x, y: plot.midY)
                .opacity(playbackPosition > 0 ? 1 : 0)
        }
        .allowsHitTesting(false)
    }
}

private struct AudioScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onDragStart: () -> Void
    let onSeek: (TimeInterval) -> Void

    @State private var isDragging = false
    @State private var dragFraction: Double = 0

    private var displayedFraction: Double {
        if isDragging { return dragFraction }
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = Metrics.Layout.scrubberTrackHeight
            let thumbSize = Metrics.Layout.scrubberThumbSize
            let width = max(1, proxy.size.width)
            let height = max(thumbSize, proxy.size.height)
            let thumbX = width * displayedFraction

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: trackHeight)
                Capsule().fill(AppColors.accent).frame(width: max(0, thumbX), height: trackHeight)
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .offset(x: min(max(thumbX - thumbSize / 2, 0), max(0, width - thumbSize)))
            }
            .frame(width: width, height: height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        if !isDragging { onDragStart() }
                        isDragging = true
                        dragFraction = fraction
                        onSeek(duration * fraction)
                    }
                    .onEnded { value in
                        let fraction = min(max(value.location.x / width, 0), 1)
                        onSeek(duration * fraction)
                        dragFraction = fraction
                        isDragging = false
                    }
            )
        }
        .frame(height: 24, alignment: .center)
    }
}

private func drawText(_ context: GraphicsContext, _ text: String, _ point: CGPoint, color: Color) {
    context.draw(context.resolve(Text(text).font(.caption2).foregroundStyle(color)), at: point, anchor: .topLeading)
}

private let spectrogramPlotBackground = Color(red: 0.02, green: 0.01, blue: 0.06)

private func waveformPlotBackground(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color(red: 0.12, green: 0.16, blue: 0.17) : Color.white
}

private func chartAxisColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.72)
}

private func chartGridColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white : Color.black
}

private func chartLabelColor(_ colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? Color.white.opacity(0.86) : Color.black.opacity(0.84)
}

private func chartPlotRect(_ size: CGSize) -> CGRect {
    CGRect(
        x: Metrics.Layout.chartAxisLeadingInset,
        y: Metrics.Layout.chartTopInset,
        width: max(1, size.width - Metrics.Layout.chartAxisLeadingInset - Metrics.Layout.chartTrailingInset),
        height: max(1, size.height - Metrics.Layout.chartTopInset - Metrics.Layout.chartBottomInset)
    )
}

private func timeTicks(duration: Double) -> [Double] {
    guard duration > 0 else { return [] }
    let step = duration <= 10 ? 1.0 : duration <= 30 ? 5.0 : 10.0
    return stride(from: 0.0, through: duration, by: step).map { $0 }
}

private func frequencyTicks(maxFrequency: Double) -> [Double] {
    guard maxFrequency > 0 else { return [] }
    let step = maxFrequency >= 100_000 ? 50_000.0 : maxFrequency >= 40_000 ? 10_000.0 : 5_000.0
    var ticks = stride(from: 0.0, through: maxFrequency, by: step).map { $0 }
    if ticks.last.map({ abs($0 - maxFrequency) > step * 0.2 }) ?? true {
        ticks.append(maxFrequency)
    }
    return ticks
}

private func frequencyLabel(_ frequency: Double) -> String {
    frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))"
}
