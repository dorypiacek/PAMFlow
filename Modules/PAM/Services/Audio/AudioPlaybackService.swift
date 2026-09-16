//
//  AudioPlaybackService.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import AVFoundation
import Combine
import Foundation

/// Playback boundary used by manual-audit audio controls.
@MainActor
protocol AudioPlaybackServicing: AnyObject {
    var isPlaying: Bool { get }
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }

    func load(
        url: URL,
        securityScopedURL: URL?,
        clipStartSeconds: TimeInterval?,
        clipDurationSeconds: TimeInterval?
    ) throws

    func play(
        url: URL,
        securityScopedURL: URL?,
        clipStartSeconds: TimeInterval?,
        clipDurationSeconds: TimeInterval?
    ) throws

    func pause()
    func seek(to time: TimeInterval)

    func prepareIfNeeded(
        url: URL,
        securityScopedURL: URL?,
        clipStartSeconds: TimeInterval?,
        clipDurationSeconds: TimeInterval?
    )

    func togglePlayback(
        url: URL,
        securityScopedURL: URL?,
        clipStartSeconds: TimeInterval?,
        clipDurationSeconds: TimeInterval?
    ) throws

    func stop()
    func displayTime(at date: Date) -> TimeInterval
}

/// Main-actor audio player used by manual audit for the selected sample.
///
/// The service keeps AVFoundation state out of SwiftUI views and exposes
/// display-friendly playback timing for smooth scrubber and playhead updates.
@MainActor
public final class AudioPlaybackService: NSObject, ObservableObject, AudioPlaybackServicing, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var duration: TimeInterval = 0
    @Published var currentTime: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var securityScopedURL: URL?
    private var timer: Timer?
    private var playbackAnchorDate: Date?
    private var playbackAnchorTime: TimeInterval = 0
    private var clipStartTime: TimeInterval = 0
    private var clipEndTime: TimeInterval?

    func load(
        url: URL,
        securityScopedURL: URL? = nil,
        clipStartSeconds: TimeInterval? = nil,
        clipDurationSeconds: TimeInterval? = nil
    ) throws {
        stop()
        if let securityScopedURL, securityScopedURL.startAccessingSecurityScopedResource() {
            self.securityScopedURL = securityScopedURL
        }

        let nextPlayer = try AVAudioPlayer(contentsOf: url)
        let start = max(0, clipStartSeconds ?? 0)
        let clipDuration = clipDurationSeconds.map { max(0, $0) }
        nextPlayer.delegate = self
        nextPlayer.prepareToPlay()
        nextPlayer.currentTime = min(start, nextPlayer.duration)
        player = nextPlayer
        clipStartTime = min(start, nextPlayer.duration)
        clipEndTime = clipDuration.map { min(clipStartTime + $0, nextPlayer.duration) }
        duration = clipEndTime.map { max(0, $0 - clipStartTime) } ?? nextPlayer.duration
        currentTime = 0
        playbackAnchorDate = nil
        playbackAnchorTime = 0
    }

    func play(
        url: URL,
        securityScopedURL: URL? = nil,
        clipStartSeconds: TimeInterval? = nil,
        clipDurationSeconds: TimeInterval? = nil
    ) throws {
        if player == nil {
            try load(
                url: url,
                securityScopedURL: securityScopedURL,
                clipStartSeconds: clipStartSeconds,
                clipDurationSeconds: clipDurationSeconds
            )
        }

        guard let player else { return }
        if let clipEndTime, player.currentTime >= clipEndTime {
            player.currentTime = clipStartTime
            currentTime = 0
        }
        isPlaying = player.play()
        if isPlaying {
            updatePlaybackAnchor(from: player)
            startTimer()
        }
    }

    func pause() {
        guard let player else { return }
        player.pause()
        currentTime = max(0, player.currentTime - clipStartTime)
        isPlaying = false
        playbackAnchorDate = nil
        playbackAnchorTime = currentTime
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clampedTime = min(max(0, time), duration)
        player.currentTime = clipStartTime + clampedTime
        currentTime = clampedTime
        updatePlaybackAnchor(from: player)
    }

    func prepareIfNeeded(
        url: URL,
        securityScopedURL: URL? = nil,
        clipStartSeconds: TimeInterval? = nil,
        clipDurationSeconds: TimeInterval? = nil
    ) {
        guard player == nil else { return }
        try? load(
            url: url,
            securityScopedURL: securityScopedURL,
            clipStartSeconds: clipStartSeconds,
            clipDurationSeconds: clipDurationSeconds
        )
    }

    func togglePlayback(
        url: URL,
        securityScopedURL: URL? = nil,
        clipStartSeconds: TimeInterval? = nil,
        clipDurationSeconds: TimeInterval? = nil
    ) throws {
        if player?.isPlaying == true {
            pause()
            return
        }

        try play(
            url: url,
            securityScopedURL: securityScopedURL,
            clipStartSeconds: clipStartSeconds,
            clipDurationSeconds: clipDurationSeconds
        )
    }

    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        isPlaying = false
        duration = 0
        currentTime = 0
        playbackAnchorDate = nil
        playbackAnchorTime = 0
        clipStartTime = 0
        clipEndTime = nil
        securityScopedURL?.stopAccessingSecurityScopedResource()
        securityScopedURL = nil
    }

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            stop()
        }
    }

    private func startTimer() {
        stopTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = self.displayTime(at: .now)
                if let clipEndTime = self.clipEndTime, player.currentTime >= clipEndTime {
                    self.stop()
                    return
                }
                self.isPlaying = player.isPlaying
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updatePlaybackAnchor(from player: AVAudioPlayer) {
        playbackAnchorDate = .now
        playbackAnchorTime = max(0, player.currentTime - clipStartTime)
    }

    func displayTime(at date: Date) -> TimeInterval {
        guard let player else {
            return currentTime
        }

        guard player.isPlaying else {
            return max(0, player.currentTime - clipStartTime)
        }

        return interpolatedPlaybackTime(for: player, at: date)
    }

    private func interpolatedPlaybackTime(for player: AVAudioPlayer, at date: Date) -> TimeInterval {
        guard let playbackAnchorDate else {
            return player.currentTime
        }

        let elapsed = date.timeIntervalSince(playbackAnchorDate)
        return min(playbackAnchorTime + elapsed, duration)
    }
}
