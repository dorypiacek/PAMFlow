//
//  AudioPreviewCacheService.swift
//  PAMFlow
//
//  Created by Dory on 17/06/2026.
//

import Foundation
import UI
import Core

/// Cached audio preview loading used by manual-audit screens.
@MainActor
protocol AudioPreviewCacheServicing: AnyObject {
    func cachedPreview(
        for url: URL,
        clipStartSeconds: Double?,
        clipDurationSeconds: Double?
    ) -> AudioPreview?

    func preview(
        from url: URL,
        securityScopedURL: URL,
        clipStartSeconds: Double?,
        clipDurationSeconds: Double?
    ) async throws -> AudioPreview

    func preheat(
        url: URL,
        securityScopedURL: URL,
        clipStartSeconds: Double?,
        clipDurationSeconds: Double?
    )

    func retainOnly(
        keys: Set<String>
    )

    func cacheKey(
        for url: URL,
        clipStartSeconds: Double?,
        clipDurationSeconds: Double?
    ) -> String

    func clear()
}

/// In-memory cache and request coalescer for generated audio previews.
///
/// Manual audit frequently moves between adjacent files. This cache prevents
/// duplicate waveform/spectrogram work and supports low-priority preheating.
@MainActor
final class AudioPreviewCacheService: AudioPreviewCacheServicing {
    private let audioPreviewService: AudioPreviewServicing
    private let cacheLimit: Int
    private var previews: [String: AudioPreview] = [:]
    private var cacheOrder: [String] = []
    private var tasks: [String: Task<AudioPreview, Error>] = [:]
    private var activeTaskCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(audioPreviewService: AudioPreviewServicing = AudioPreviewService(), cacheLimit: Int = 11) {
        self.audioPreviewService = audioPreviewService
        self.cacheLimit = cacheLimit
    }

    func cachedPreview(
        for url: URL,
        clipStartSeconds: Double? = nil,
        clipDurationSeconds: Double? = nil
    ) -> AudioPreview? {
        previews[cacheKey(for: url, clipStartSeconds: clipStartSeconds, clipDurationSeconds: clipDurationSeconds)]
    }

    func preview(
        from url: URL,
        securityScopedURL: URL,
        clipStartSeconds: Double? = nil,
        clipDurationSeconds: Double? = nil
    ) async throws -> AudioPreview {
        let key = cacheKey(for: url, clipStartSeconds: clipStartSeconds, clipDurationSeconds: clipDurationSeconds)

        if let preview = previews[key] {
            AppLog.info("Audio preview cache hit for \(url.lastPathComponent)")
            rememberCacheUse(for: key)
            return preview
        }

        if let task = tasks[key] {
            AppLog.info("Audio preview awaiting existing task for \(url.lastPathComponent)")
            return try await task.value
        }

        AppLog.info("Audio preview cache loading \(url.lastPathComponent)")
        let service = audioPreviewService
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            await self?.waitForPreviewSlot()
            defer {
                Task { @MainActor [weak self] in
                    self?.releasePreviewSlot()
                }
            }

            let accessed = securityScopedURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    securityScopedURL.stopAccessingSecurityScopedResource()
                }
            }

            return try service.loadPreview(
                from: url,
                clipStartSeconds: clipStartSeconds,
                clipDurationSeconds: clipDurationSeconds
            )
        }

        tasks[key] = task
        do {
            let preview = try await task.value
            tasks[key] = nil
            store(preview, for: key)
            return preview
        } catch {
            tasks[key] = nil
            throw error
        }
    }

    func preheat(
        url: URL,
        securityScopedURL: URL,
        clipStartSeconds: Double? = nil,
        clipDurationSeconds: Double? = nil
    ) {
        let key = cacheKey(for: url, clipStartSeconds: clipStartSeconds, clipDurationSeconds: clipDurationSeconds)
        guard previews[key] == nil, tasks[key] == nil else {
            return
        }

        AppLog.info("Audio preview preheating \(url.lastPathComponent)")
        let service = audioPreviewService
        tasks[key] = Task.detached(priority: .utility) { [weak self] in
            await self?.waitForPreviewSlot()
            defer {
                Task { @MainActor [weak self] in
                    self?.releasePreviewSlot()
                }
            }

            let accessed = securityScopedURL.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    securityScopedURL.stopAccessingSecurityScopedResource()
                }
            }

            return try service.loadPreview(
                from: url,
                clipStartSeconds: clipStartSeconds,
                clipDurationSeconds: clipDurationSeconds
            )
        }

        Task { [weak self] in
            guard let self, let task = tasks[key] else { return }
            do {
                let preview = try await task.value
                tasks[key] = nil
                store(preview, for: key)
                AppLog.info("Audio preview preheated \(url.lastPathComponent)")
            } catch {
                tasks[key] = nil
                AppLog.info("Audio preview preheat failed for \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    func retainOnly(keys retainedKeys: Set<String>) {
        for key in tasks.keys where !retainedKeys.contains(key) {
            tasks[key]?.cancel()
            tasks[key] = nil
        }
        for key in previews.keys where !retainedKeys.contains(key) {
            previews[key] = nil
        }
        cacheOrder.removeAll { !retainedKeys.contains($0) }
    }

    func clear() {
        for task in tasks.values {
            task.cancel()
        }
        tasks.removeAll()
        previews.removeAll(keepingCapacity: false)
        cacheOrder.removeAll(keepingCapacity: false)
        while !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
        activeTaskCount = 0
    }

    private func waitForPreviewSlot() async {
        if activeTaskCount < 1 {
            activeTaskCount += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func releasePreviewSlot() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
            return
        }

        activeTaskCount = max(0, activeTaskCount - 1)
    }

    private func store(_ preview: AudioPreview, for key: String) {
        previews[key] = preview
        rememberCacheUse(for: key)

        while cacheOrder.count > cacheLimit {
            let removedKey = cacheOrder.removeFirst()
            previews[removedKey] = nil
        }
    }

    private func rememberCacheUse(for key: String) {
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
    }

    func cacheKey(
        for url: URL,
        clipStartSeconds: Double? = nil,
        clipDurationSeconds: Double? = nil
    ) -> String {
        let path = url.standardizedFileURL.path
        guard let clipStartSeconds, let clipDurationSeconds else {
            return path
        }
        return "\(path)#\(String(format: "%.6f", clipStartSeconds))+\(String(format: "%.6f", clipDurationSeconds))"
    }
}
