//
//  SettingsView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import AppKit
import SwiftUI

/// Preferences panel for appearance, feedback, and logout.
struct SettingsView: View {
    @Environment(AppCoordinator.self) private var appCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackEmail = ""
    @State private var feedbackSubject = ""
    @State private var feedbackMessage = ""
    @State private var feedbackAttachments: [URL] = []
    @State private var feedbackStatus: String?
    @State private var isShowingFeedbackPage = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                if isShowingFeedbackPage {
                    feedbackPage
                } else {
                    settingsPage
                }
            }
            .padding(Spacing.xLarge)
        }
        .frame(width: Metrics.Layout.settingsWidth)
        .frame(maxHeight: 760)
        .glassySurface()
    }

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Text(Strings.Settings.title)
                .font(Fonts.sectionTitle)

            appearanceSection

            Button {
                isShowingFeedbackPage = true
            } label: {
                Label(Strings.Settings.feedbackTitle, systemImage: "envelope")
            }
            .buttonStyle(.secondaryAction)

            Divider()

            HStack(alignment: .bottom) {
                aboutSection

                Spacer()

                HStack {
                    Button(Strings.Settings.logOutButton, role: .destructive) {
                        appCoordinator.signOut()
                        dismiss()
                    }
                    .buttonStyle(.secondaryAction)

                    Button(Strings.Settings.doneButton) {
                        dismiss()
                    }
                    .buttonStyle(.primaryAction)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(Strings.Settings.appearanceTitle)
                .font(Fonts.body.bold())

            Picker("", selection: themeBinding) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(Strings.Settings.aboutTitle)
                .font(Fonts.body.bold())

            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                settingsInfoRow(title: Strings.Settings.version, value: versionString)

                HStack(spacing: Spacing.xSmall) {
                    Text(Strings.Settings.copyright)
                        .foregroundStyle(.secondary)
                    Button(Strings.Settings.copyrightOwner) {
                        openCopyrightLink()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.accent)
                    .accessibilityLabel(Strings.Settings.copyrightOwner)
                }
            }
            .font(Fonts.caption)
        }
    }

    private var feedbackPage: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack {
                Button {
                    isShowingFeedbackPage = false
                } label: {
                    Label(Strings.Settings.backButton, systemImage: "chevron.left")
                }
                .buttonStyle(.secondaryAction)

                Spacer()
            }

            Text(Strings.Settings.feedbackTitle)
                .font(Fonts.sectionTitle)

            TextField(Strings.Settings.feedbackEmailPlaceholder, text: $feedbackEmail)
                .textFieldStyle(.roundedBorder)
            TextField(Strings.Settings.feedbackSubjectPlaceholder, text: $feedbackSubject)
                .textFieldStyle(.roundedBorder)
            TextEditor(text: $feedbackMessage)
                .frame(minHeight: 96)
                .scrollContentBackground(.hidden)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Metrics.Layout.rowCornerRadius, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if feedbackMessage.isEmpty {
                        Text(Strings.Settings.feedbackMessagePlaceholder)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Spacing.small)
                            .padding(.vertical, 7)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                Button {
                    selectFeedbackAttachments()
                } label: {
                    Label(Strings.Settings.addAttachmentsButton, systemImage: "paperclip")
                }
                .buttonStyle(.secondaryAction)

                Text(attachmentSummary)
                    .font(Fonts.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(feedbackAttachments, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        feedbackAttachments.removeAll { $0 == url }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.iconAction)
                }
                .font(Fonts.caption)
            }

            Button(Strings.Settings.sendFeedbackButton) {
                sendFeedback()
            }
            .buttonStyle(.primaryAction)
            .disabled(feedbackSubject.trimmed.isEmpty || feedbackMessage.trimmed.isEmpty)

            if let feedbackStatus {
                Text(feedbackStatus)
                    .font(Fonts.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { appCoordinator.selectedTheme },
            set: { appCoordinator.selectTheme($0) }
        )
    }

    private var attachmentSummary: String {
        let total = feedbackAttachments.reduce(0) { partialResult, url in
            partialResult + fileSize(url)
        }
        return "\(feedbackAttachments.count) files, \(ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)) / \(Strings.Settings.maxAttachmentSizeLabel)"
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let version, let build else { return Strings.Common.unknown }
        return String(format: Strings.Settings.versionFormat, version, build)
    }

    private func selectFeedbackAttachments() {
        let panel = NSOpenPanel()
        panel.title = Strings.Settings.addAttachmentsButton
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        let existingSize = feedbackAttachments.reduce(0) { $0 + fileSize($1) }
        var nextAttachments = feedbackAttachments
        var totalSize = existingSize
        for url in panel.urls {
            let size = fileSize(url)
            guard totalSize + size <= Strings.Settings.maxAttachmentBytes else {
                feedbackStatus = Strings.Settings.attachmentLimitMessage
                break
            }
            if !nextAttachments.contains(url) {
                nextAttachments.append(url)
                totalSize += size
            }
        }
        feedbackAttachments = nextAttachments
    }

    private func sendFeedback() {
        let sender = feedbackEmail.trimmed
        let body = sender.isEmpty
            ? feedbackMessage.trimmed
            : """
            Reply email: \(sender)

            \(feedbackMessage.trimmed)
            """
        let service = NSSharingService(named: .composeEmail)
        service?.recipients = [FeedbackRoute.recipient]
        service?.subject = feedbackSubject.trimmed

        let items: [Any] = [body] + feedbackAttachments
        if service?.canPerform(withItems: items) == true {
            service?.perform(withItems: items)
            feedbackStatus = Strings.Settings.feedbackOpenedMessage
        } else {
            openFeedbackMailto(body: body)
        }
    }

    private func openFeedbackMailto(body: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = FeedbackRoute.recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: feedbackSubject.trimmed),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
            feedbackStatus = Strings.Settings.feedbackOpenedMessage
        }
    }

    private func openCopyrightLink() {
        guard let url = URL(string: Strings.Settings.copyrightURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func fileSize(_ url: URL) -> Int {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
    }

    private func settingsInfoRow(title: String, value: String) -> some View {
        HStack(spacing: Spacing.small) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }
}

private enum FeedbackRoute {
    static var recipient: String {
        ["dory", "piacek"].joined(separator: ".") + "@" + ["icloud", "com"].joined(separator: ".")
    }
}
