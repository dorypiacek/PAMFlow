//
//  AudioPreviewModels.swift
//  PAMFlow
//
//  Created by Dory on 13/09/2026.
//

import Foundation

/// Render-ready waveform and spectrogram data for one previewable media item.
public struct AudioPreview: Equatable, Sendable {
    public var waveformPeaks: [WaveformPeak]
    public var spectrogramBins: [[Float]]
    public var spectrogramMaxFrequencyHz: Double
    public var durationSeconds: Double
    public var sampleRateHz: Double

    public init(
        waveformPeaks: [WaveformPeak],
        spectrogramBins: [[Float]],
        spectrogramMaxFrequencyHz: Double,
        durationSeconds: Double,
        sampleRateHz: Double
    ) {
        self.waveformPeaks = waveformPeaks
        self.spectrogramBins = spectrogramBins
        self.spectrogramMaxFrequencyHz = spectrogramMaxFrequencyHz
        self.durationSeconds = durationSeconds
        self.sampleRateHz = sampleRateHz
    }
}

/// Minimum and maximum amplitude for one downsampled waveform bucket.
public struct WaveformPeak: Equatable, Sendable {
    public var minimum: Float
    public var maximum: Float

    public init(minimum: Float, maximum: Float) {
        self.minimum = minimum
        self.maximum = maximum
    }
}
