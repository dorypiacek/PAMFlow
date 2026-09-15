//
//  FileSelectionService.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Abstraction for choosing folders from UI code.
///
/// Keeping this as a protocol lets feature models be tested without presenting
/// AppKit panels.
@MainActor
public protocol FileSelecting {
    /// Presents folder selection and returns the chosen folder URL, if any.
    func selectFolder(title: String, message: String) -> URL?

    /// Presents a mixed source selector and returns either one folder or multiple files.
    func selectInputSource(title: String, message: String) -> ProjectInputSourceSelection?

    /// Presents a mixed source selector, optionally restricting visible files by extension.
    func selectInputSource(title: String, message: String, allowedFileExtensions: Set<String>?) -> ProjectInputSourceSelection?

    /// Presents a folder selector to reacquire write access to a project container.
    func selectWritableProjectContainer(title: String, message: String, defaultURL: URL?) -> URL?

    /// Presents a save destination panel and returns the selected destination URL.
    func selectSaveDestination(defaultName: String, canCreateDirectories: Bool) -> URL?
}

/// System file-opening actions used by lightweight UI helpers.
@MainActor
public protocol FileOpening {
    static func revealInFinder(_ url: URL)
    static func open(_ url: URL)
}

/// AppKit-backed implementation of folder selection for macOS.
@MainActor
public final class FileSelectionService: FileSelecting, FileOpening {
    public init() {}

    public func selectFolder(title: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Select"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        return panel.runModal() == .OK ? panel.url : nil
    }

    public func selectInputSource(title: String, message: String) -> ProjectInputSourceSelection? {
        selectInputSource(title: title, message: message, allowedFileExtensions: nil)
    }

    public func selectInputSource(
        title: String,
        message: String,
        allowedFileExtensions: Set<String>?
    ) -> ProjectInputSourceSelection? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Select"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        if let allowedFileExtensions, !allowedFileExtensions.isEmpty {
            panel.allowedContentTypes = allowedFileExtensions
                .sorted()
                .compactMap { UTType(filenameExtension: $0) }
        }

        guard panel.runModal() == .OK else { return nil }
        let urls = panel.urls
        guard !urls.isEmpty else { return nil }

        if urls.count == 1, let url = urls.first, isDirectory(url) {
            return .folder(url)
        }

        let files = urls.filter { !isDirectory($0) }
        guard !files.isEmpty else { return nil }
        return .files(files)
    }

    public func selectWritableProjectContainer(title: String, message: String, defaultURL: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Allow"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = defaultURL

        return panel.runModal() == .OK ? panel.url : nil
    }

    public func selectSaveDestination(defaultName: String, canCreateDirectories: Bool) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = canCreateDirectories
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Reveals a file or folder in Finder.
    public static func revealInFinder(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    /// Opens a URL with the system default app.
    public static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}

public enum ProjectInputSourceSelection: Equatable {
    case folder(URL)
    case files([URL])

    public var displayURL: URL? {
        switch self {
        case .folder(let url):
            return url
        case .files(let urls):
            return urls.first
        }
    }

    public var displayText: String {
        switch self {
        case .folder(let url):
            return url.path
        case .files(let urls):
            if urls.count == 1 {
                return urls[0].path
            }
            return "\(urls.count) files selected"
        }
    }

    public var rawMediaFolderURL: URL? {
        switch self {
        case .folder(let url):
            return url
        case .files(let urls):
            return urls.first?.deletingLastPathComponent()
        }
    }
}
