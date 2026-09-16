//
//  PAMGuardRunHelpView.swift
//  PAMFlow
//
//  Created by Dory on 03/07/2026.
//

import AppKit
import UI
import Core
import SwiftUI

/// Renders step-by-step instructions for running the generated PAMGuard template outside the app.
struct PAMGuardRunHelpView: View {
    /// Optional action that reveals the generated PAMGuard project folder in Finder.
    let onShowPamguardFolder: (() -> Void)?
    /// Action used to dismiss the help sheet.
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(PAMStrings.Setup.helpTitle)
                    .font(Fonts.screenTitle)

                Spacer()

                if let onShowPamguardFolder {
                    Button(PAMStrings.Setup.showInFinder, action: onShowPamguardFolder)
                        .buttonStyle(.primaryAction)
                }

                Button(Strings.Common.close, action: onClose)
                    .buttonStyle(.secondaryAction)
            }
            .padding(Spacing.large)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    ForEach(Self.steps) { step in
                        PAMGuardHelpStepView(step: step)
                    }
                }
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.large)
            }
        }
        .frame(minWidth: 720, idealWidth: 860, minHeight: 620, idealHeight: 760)
        .background(AppColors.background)
    }
}

private struct PAMGuardHelpStepView: View {
    /// Instructional step rendered by this row.
    let step: PAMGuardHelpStep

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text("\(step.number).")
                    .font(Fonts.subtitle.bold())
                    .foregroundStyle(.tint)
                    .frame(width: 28, alignment: .trailing)

                Text(step.title)
                    .font(Fonts.subtitle.bold())
            }

            if let detail = step.detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 40)
            }

            if let link = step.link {
                Link(link.title, destination: link.url)
                    .padding(.leading, 40)
            }

            ForEach(step.images, id: \.self) { imageName in
                PAMGuardHelpImage(name: imageName)
                    .padding(.leading, 40)
            }
        }
    }
}

private struct PAMGuardHelpImage: View {
    private enum Assets {
        static let imageExtension = "png"
        static let imageSubdirectory = "PAMGuardHelp"
    }

    /// Image asset name displayed for an instructional step.
    let name: String

    var body: some View {
        if let image = loadImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.separator, lineWidth: 1)
                }
                .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private func loadImage() -> NSImage? {
        let packageFlatURL = Bundle.module.url(forResource: name, withExtension: Assets.imageExtension)
        let packageNestedURL = Bundle.module.url(
            forResource: name,
            withExtension: Assets.imageExtension,
            subdirectory: Assets.imageSubdirectory
        )
        let appNestedURL = Bundle.main.url(
            forResource: name,
            withExtension: Assets.imageExtension,
            subdirectory: Assets.imageSubdirectory
        )
        let appFlatURL = Bundle.main.url(forResource: name, withExtension: Assets.imageExtension)

        guard let url = packageFlatURL ?? packageNestedURL ?? appNestedURL ?? appFlatURL else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

private struct PAMGuardHelpStep: Identifiable {
    /// One-based step number shown in the help sheet.
    let number: Int
    /// Short instruction shown as the step heading.
    let title: String
    /// Optional supporting instruction text.
    let detail: String?
    /// Optional external documentation or download link.
    let link: PAMGuardHelpLink?
    /// Ordered screenshot asset names displayed below the step.
    let images: [String]

    /// Stable identifier used by SwiftUI lists.
    var id: Int { number }
}

private struct PAMGuardHelpLink {
    /// Link text shown in the help sheet.
    let title: String
    /// Destination opened when the user activates the link.
    let url: URL
}

private extension PAMGuardRunHelpView {
    /// Ordered PAMGuard run instructions displayed in the help sheet.
    static let steps: [PAMGuardHelpStep] = [
        PAMGuardHelpStep(
            number: 1,
            title: PAMStrings.Setup.helpDownloadStep,
            detail: nil,
            link: PAMGuardHelpLink(
                title: PAMStrings.Setup.helpDownloadLink,
                url: URL(string: "https://www.pamguard.org/releases/V2_02_18.html")!
            ),
            images: []
        ),
        PAMGuardHelpStep(
            number: 2,
            title: PAMStrings.Setup.helpStep1,
            detail: nil,
            link: nil,
            images: []
        ),
        PAMGuardHelpStep(
            number: 3,
            title: PAMStrings.Setup.helpStep2,
            detail: nil,
            link: nil,
            images: []
        ),
        PAMGuardHelpStep(
            number: 4,
            title: PAMStrings.Setup.helpStep3,
            detail: nil,
            link: nil,
            images: ["database-menu", "database-selection"]
        ),
        PAMGuardHelpStep(
            number: 5,
            title: PAMStrings.Setup.helpStep4,
            detail: nil,
            link: nil,
            images: ["binary-menu", "binary-folder"]
        ),
        PAMGuardHelpStep(
            number: 6,
            title: PAMStrings.Setup.helpStep5,
            detail: nil,
            link: nil,
            images: ["sound-acquisition-menu", "sound-input-folder"]
        ),
        PAMGuardHelpStep(
            number: 7,
            title: PAMStrings.Setup.helpStep6,
            detail: nil,
            link: nil,
            images: []
        ),
        PAMGuardHelpStep(
            number: 8,
            title: PAMStrings.Setup.helpStep7,
            detail: nil,
            link: nil,
            images: []
        )
    ]
}
