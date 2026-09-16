//
//  BRUVManualAuditPreview.swift
//  PAMFlow
//
//  Created by Dory on 15/09/2026.
//

import AppKit
import Core
import SwiftUI
import UI

/// BRUV-owned preview content for frame-based detection review.
struct BRUVManualAuditPreview: View {
    let viewModel: BRUVManualAuditViewModel
    let project: Project
    let file: ProjectScanFile

    @State private var image: NSImage?
    @State private var loadedPath: String?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.Layout.rowCornerRadius))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(Strings.ManualAudit.previewUnavailable)
                    .foregroundStyle(AppColors.error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .task(id: file.relativePath) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = viewModel.imagePreviewURL(file: file, project: project) else {
            image = nil
            loadedPath = nil
            return
        }

        let path = url.standardizedFileURL.path
        guard loadedPath != path else { return }
        loadedPath = path
        let scopedURL = url.path.hasPrefix(project.rootFolderURL?.path ?? "")
            ? project.rootFolderURL
            : project.inputFolderURL
        let loadedImage = await Task.detached(priority: .userInitiated) {
            let accessed = scopedURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if accessed {
                    scopedURL?.stopAccessingSecurityScopedResource()
                }
            }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                return nil as NSImage?
            }
            return NSImage(data: data)
        }.value
        image = loadedImage
    }
}
