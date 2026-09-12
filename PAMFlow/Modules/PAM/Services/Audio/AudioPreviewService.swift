//
//  AudioPreviewService.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import Accelerate
import AVFoundation
import Foundation

/// Render-ready waveform and spectrogram data for one audio file.
struct AudioPreview: Equatable, Sendable {
    var waveformPeaks: [WaveformPeak]
    var spectrogramBins: [[Float]]
    var spectrogramMaxFrequencyHz: Double
    var durationSeconds: Double
    var sampleRateHz: Double
}

/// Minimum and maximum amplitude for a downsampled waveform bucket.
struct WaveformPeak: Equatable, Sendable {
    var minimum: Float
    var maximum: Float
}

/// Generates waveform and spectrogram previews for audio media.
protocol AudioPreviewServicing: Sendable {
    nonisolated func loadPreview(
        from url: URL,
        clipStartSeconds: Double?,
        clipDurationSeconds: Double?
    ) throws -> AudioPreview
}

/// Generates waveform envelopes and spectrogram bins from WAV files.
///
/// This type is nonisolated so CPU-heavy work can run off the main actor via
/// `Task.detached` while the UI remains responsive.
final class AudioPreviewService: AudioPreviewServicing {
    private nonisolated static let spectrogramDisplayRangeDB: Float = 60

    enum AudioPreviewError: LocalizedError {
        case unreadableAudio
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .unreadableAudio:
                "This audio file could not be opened."
            case .emptyAudio:
                "This audio file does not contain readable samples."
            }
        }
    }

    nonisolated init() {}

    nonisolated func loadPreview(
        from url: URL,
        clipStartSeconds: Double? = nil,
        clipDurationSeconds: Double? = nil
    ) throws -> AudioPreview {
        let file = try AVAudioFile(forReading: url)
        let frameCount = file.length
        guard frameCount > 0 else { throw AudioPreviewError.emptyAudio }

        if let clipStartSeconds, let clipDurationSeconds {
            return try clippedPreview(
                from: file,
                clipStartSeconds: clipStartSeconds,
                clipDurationSeconds: clipDurationSeconds
            )
        }

        let spectrogram = try spectrogram(from: file, columns: 2_400, bins: 768)
        return AudioPreview(
            waveformPeaks: try waveformEnvelope(from: file, targetCount: 2_400),
            spectrogramBins: spectrogram.bins,
            spectrogramMaxFrequencyHz: spectrogram.maxFrequencyHz,
            durationSeconds: Double(frameCount) / file.processingFormat.sampleRate,
            sampleRateHz: file.processingFormat.sampleRate
        )
    }

    private nonisolated func clippedPreview(
        from file: AVAudioFile,
        clipStartSeconds: Double,
        clipDurationSeconds: Double
    ) throws -> AudioPreview {
        let sampleRate = file.processingFormat.sampleRate
        let totalFrames = Int(file.length)
        let startFrame = min(max(0, Int((clipStartSeconds * sampleRate).rounded(.down))), max(0, totalFrames - 1))
        let requestedFrames = max(Int((clipDurationSeconds * sampleRate).rounded(.up)), Int(sampleRate * 0.05))
        let framesToRead = min(requestedFrames, totalFrames - startFrame)
        guard framesToRead > 0 else { throw AudioPreviewError.emptyAudio }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(framesToRead)
        ) else {
            throw AudioPreviewError.unreadableAudio
        }

        file.framePosition = AVAudioFramePosition(startFrame)
        try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
        guard let channelData = buffer.floatChannelData else {
            throw AudioPreviewError.unreadableAudio
        }

        let readFrames = Int(buffer.frameLength)
        guard readFrames > 0 else { throw AudioPreviewError.emptyAudio }

        var samples = Array(repeating: Float(0), count: readFrames)
        for frame in 0..<readFrames {
            samples[frame] = monoSample(
                from: channelData,
                channels: Int(buffer.format.channelCount),
                frame: frame
            )
        }

        let spectrogram = try spectrogram(from: samples, sampleRate: sampleRate, columns: 2_400, bins: 768)
        return AudioPreview(
            waveformPeaks: waveformEnvelope(from: samples, targetCount: 1_600),
            spectrogramBins: spectrogram.bins,
            spectrogramMaxFrequencyHz: spectrogram.maxFrequencyHz,
            durationSeconds: Double(readFrames) / sampleRate,
            sampleRateHz: sampleRate
        )
    }

    private nonisolated func waveformEnvelope(from file: AVAudioFile, targetCount: Int) throws -> [WaveformPeak] {
        let frameCount = Int(file.length)
        let bucketCount = min(targetCount, max(1, frameCount))
        var minimums = Array(repeating: Float.greatestFiniteMagnitude, count: bucketCount)
        var maximums = Array(repeating: -Float.greatestFiniteMagnitude, count: bucketCount)
        let chunkSize = 65_536

        file.framePosition = 0
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(chunkSize)) else {
            throw AudioPreviewError.unreadableAudio
        }

        var globalFrame = 0
        while globalFrame < frameCount {
            let framesToRead = min(chunkSize, frameCount - globalFrame)
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: AVAudioFrameCount(framesToRead))
            guard let channelData = buffer.floatChannelData else {
                throw AudioPreviewError.unreadableAudio
            }

            let readFrames = Int(buffer.frameLength)
            for frame in 0..<readFrames {
                let bucket = min(bucketCount - 1, ((globalFrame + frame) * bucketCount) / frameCount)
                let sample = monoSample(from: channelData, channels: Int(buffer.format.channelCount), frame: frame)
                minimums[bucket] = min(minimums[bucket], sample)
                maximums[bucket] = max(maximums[bucket], sample)
            }

            globalFrame += readFrames
            if readFrames == 0 { break }
        }

        return (0..<bucketCount).map { index in
            let minimum = minimums[index] == Float.greatestFiniteMagnitude ? 0 : minimums[index]
            let maximum = maximums[index] == -Float.greatestFiniteMagnitude ? 0 : maximums[index]
            return WaveformPeak(minimum: minimum, maximum: maximum)
        }
    }

    private nonisolated func waveformEnvelope(from samples: [Float], targetCount: Int) -> [WaveformPeak] {
        let frameCount = samples.count
        let bucketCount = min(targetCount, max(1, frameCount))
        var minimums = Array(repeating: Float.greatestFiniteMagnitude, count: bucketCount)
        var maximums = Array(repeating: -Float.greatestFiniteMagnitude, count: bucketCount)

        for frame in samples.indices {
            let bucket = min(bucketCount - 1, (frame * bucketCount) / frameCount)
            let sample = samples[frame]
            minimums[bucket] = min(minimums[bucket], sample)
            maximums[bucket] = max(maximums[bucket], sample)
        }

        return (0..<bucketCount).map { index in
            let minimum = minimums[index] == Float.greatestFiniteMagnitude ? 0 : minimums[index]
            let maximum = maximums[index] == -Float.greatestFiniteMagnitude ? 0 : maximums[index]
            return WaveformPeak(minimum: minimum, maximum: maximum)
        }
    }

    private nonisolated func spectrogram(from file: AVAudioFile, columns: Int, bins: Int) throws -> SpectrogramData {
        let windowSize = 4096
        let frameCount = Int(file.length)
        let sampleRate = file.processingFormat.sampleRate
        guard frameCount >= windowSize else {
            return SpectrogramData(bins: [], maxFrequencyHz: max(sampleRate / 2, 1))
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(windowSize)) else {
            throw AudioPreviewError.unreadableAudio
        }

        let step = max(1, (frameCount - windowSize) / max(1, columns - 1))
        var spectra: [[Float]] = []
        let window = hannWindow(size: windowSize)
        let log2WindowSize = vDSP_Length(log2(Float(windowSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2WindowSize, FFTRadix(kFFTRadix2)) else {
            throw AudioPreviewError.unreadableAudio
        }
        defer {
            vDSP_destroy_fftsetup(fftSetup)
        }

        for column in 0..<columns {
            let start = min(column * step, frameCount - windowSize)
            file.framePosition = AVAudioFramePosition(start)
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: AVAudioFrameCount(windowSize))
            guard let channelData = buffer.floatChannelData, Int(buffer.frameLength) == windowSize else {
                throw AudioPreviewError.unreadableAudio
            }

            var samples = Array(repeating: Float(0), count: windowSize)
            for sampleIndex in 0..<windowSize {
                samples[sampleIndex] = monoSample(
                    from: channelData,
                    channels: Int(buffer.format.channelCount),
                    frame: sampleIndex
                ) * window[sampleIndex]
            }

            let spectrum = fftMagnitudes(samples: samples, setup: fftSetup, log2WindowSize: log2WindowSize)
            spectra.append(decibelSpectrum(spectrum))
        }

        return normalizedSpectrogram(from: spectra, bins: bins, sampleRate: sampleRate)
    }

    private nonisolated func spectrogram(
        from samples: [Float],
        sampleRate: Double,
        columns: Int,
        bins: Int
    ) throws -> SpectrogramData {
        let windowSize = min(4096, max(128, previousPowerOfTwo(samples.count)))
        guard samples.count >= windowSize else {
            return SpectrogramData(bins: [], maxFrequencyHz: max(sampleRate / 2, 1))
        }

        let step = max(1, (samples.count - windowSize) / max(1, columns - 1))
        var spectra: [[Float]] = []
        let window = hannWindow(size: windowSize)
        let log2WindowSize = vDSP_Length(log2(Float(windowSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2WindowSize, FFTRadix(kFFTRadix2)) else {
            throw AudioPreviewError.unreadableAudio
        }
        defer {
            vDSP_destroy_fftsetup(fftSetup)
        }

        for column in 0..<columns {
            let start = min(column * step, samples.count - windowSize)
            let windowedSamples = (0..<windowSize).map { samples[start + $0] * window[$0] }
            let spectrum = fftMagnitudes(samples: windowedSamples, setup: fftSetup, log2WindowSize: log2WindowSize)
            spectra.append(decibelSpectrum(spectrum))
        }

        return normalizedSpectrogram(from: spectra, bins: bins, sampleRate: sampleRate)
    }

    private nonisolated func decibelSpectrum(_ spectrum: [Float]) -> [Float] {
        spectrum.map { value in
            20 * log10(max(sqrt(value), 0.000_000_1))
        }
    }

    private nonisolated func normalizedSpectrogram(
        from spectra: [[Float]],
        bins: Int,
        sampleRate: Double
    ) -> SpectrogramData {
        guard let firstSpectrum = spectra.first, !firstSpectrum.isEmpty else {
            return SpectrogramData(bins: [], maxFrequencyHz: max(sampleRate / 2, 1))
        }

        let nyquist = max(sampleRate / 2, 1)
        let maxSpectrumIndex = firstSpectrum.count - 1
        var output: [[Float]] = []
        var globalMaximum: Float = -.greatestFiniteMagnitude

        for spectrum in spectra {
            var magnitudes = Array(repeating: Float(0), count: bins)
            for bin in 0..<bins {
                let lower = (bin * maxSpectrumIndex) / bins
                let upper = max(lower + 1, ((bin + 1) * maxSpectrumIndex) / bins)
                let range = lower..<min(upper, spectrum.count)
                let average = range.reduce(Float(0)) { $0 + spectrum[$1] } / Float(max(1, range.count))
                globalMaximum = max(globalMaximum, average)
                magnitudes[bin] = average
            }
            output.append(magnitudes)
        }

        let normalized = output.map { column in
            column.map { value in
                min(1, max(0, (value - (globalMaximum - Self.spectrogramDisplayRangeDB)) / Self.spectrogramDisplayRangeDB))
            }
        }

        return SpectrogramData(bins: normalized, maxFrequencyHz: nyquist)
    }

    private nonisolated func fftMagnitudes(
        samples: [Float],
        setup: FFTSetup,
        log2WindowSize: vDSP_Length
    ) -> [Float] {
        var real = Array(repeating: Float(0), count: samples.count / 2)
        var imaginary = Array(repeating: Float(0), count: samples.count / 2)
        var magnitudes = Array(repeating: Float(0), count: samples.count / 2)

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var splitComplex = DSPSplitComplex(
                    realp: realPointer.baseAddress!,
                    imagp: imaginaryPointer.baseAddress!
                )

                samples.withUnsafeBufferPointer { samplesPointer in
                    samplesPointer.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: samples.count / 2) { complexPointer in
                        vDSP_ctoz(complexPointer, 2, &splitComplex, 1, vDSP_Length(samples.count / 2))
                    }
                }

                vDSP_fft_zrip(setup, &splitComplex, 1, log2WindowSize, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(samples.count / 2))
            }
        }

        return magnitudes
    }

    private nonisolated func hannWindow(size: Int) -> [Float] {
        guard size > 1 else { return [1] }

        return (0..<size).map { index in
            0.5 - 0.5 * cos(2 * Float.pi * Float(index) / Float(size - 1))
        }
    }

    private nonisolated func monoSample(
        from channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channels: Int,
        frame: Int
    ) -> Float {
        guard channels > 0 else { return 0 }

        var value: Float = 0
        for channel in 0..<channels {
            value += channelData[channel][frame]
        }
        return value / Float(channels)
    }

    private nonisolated func previousPowerOfTwo(_ value: Int) -> Int {
        guard value > 0 else { return 0 }
        var result = 1
        while result * 2 <= value {
            result *= 2
        }
        return result
    }
}

private struct SpectrogramData {
    var bins: [[Float]]
    var maxFrequencyHz: Double
}
