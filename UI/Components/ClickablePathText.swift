//
//  ClickablePathText.swift
//  PAMFlow
//
//  Created by Dory on 08/07/2026.
//

import SwiftUI

struct ClickablePathText: View {
    let path: String
    var lineLimit: Int = 2

    var body: some View {
        Button {
            openInFinder()
        } label: {
            Text(path.isEmpty ? Strings.Common.unknown : path)
                .lineLimit(lineLimit)
                .truncationMode(.middle)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help(Strings.Common.showInFinder)
        .disabled(!canOpen)
    }

    private func openInFinder() {
        FileSelectionService.revealInFinder(URL(fileURLWithPath: path))
    }

    private var canOpen: Bool {
        path.hasPrefix("/")
    }
}
