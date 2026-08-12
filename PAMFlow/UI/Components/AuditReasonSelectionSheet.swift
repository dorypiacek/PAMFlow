//
//  AuditReasonSelectionSheet.swift
//  PAMFlow
//
//  Created by Dory on 04/07/2026.
//

import SwiftUI

struct AuditReasonConfiguration: Equatable {
    var title: String
    var options: [String]
    var textOnly: Bool
    var isRequired: Bool

    static func manualAudit() -> AuditReasonConfiguration {
        AuditReasonConfiguration(
            title: Strings.AuditReason.addReason,
            options: [Strings.AuditReason.deploymentNoise, Strings.AuditReason.fileCorrupted, Strings.Common.other],
            textOnly: false,
            isRequired: true
        )
    }

    static func pamDetectionReview() -> AuditReasonConfiguration {
        AuditReasonConfiguration(
            title: Strings.AuditReason.addReason,
            options: [Strings.AuditReason.falsePositive, Strings.Common.other],
            textOnly: false,
            isRequired: true
        )
    }

    static func freeTextOptional() -> AuditReasonConfiguration {
        AuditReasonConfiguration(
            title: Strings.AuditReason.addReason,
            options: [],
            textOnly: true,
            isRequired: false
        )
    }
}

struct AuditReasonSelectionSheet: View {
    let configuration: AuditReasonConfiguration
    let currentReason: String
    let onSave: (String) -> Void
    let onClose: () -> Void

    @State private var selectedOption: String
    @State private var detailText: String

    init(
        configuration: AuditReasonConfiguration,
        currentReason: String,
        onSave: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.currentReason = currentReason
        self.onSave = onSave
        self.onClose = onClose

        if configuration.textOnly {
            _selectedOption = State(initialValue: "")
            _detailText = State(initialValue: currentReason)
        } else if configuration.options.contains(currentReason) {
            _selectedOption = State(initialValue: currentReason)
            _detailText = State(initialValue: "")
        } else if currentReason.isEmpty {
            _selectedOption = State(initialValue: configuration.options.first ?? "")
            _detailText = State(initialValue: "")
        } else {
            _selectedOption = State(initialValue: Strings.Common.other)
            _detailText = State(initialValue: currentReason)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            header

            if configuration.textOnly {
                TextField(Strings.AuditReason.reason, text: $detailText, axis: .vertical)
                    .textFieldStyle(.appGlassMultiline)
                    .foregroundStyle(.primary)
                    .lineLimit(3...6)
            } else {
                Picker(Strings.AuditReason.reason, selection: $selectedOption) {
                    ForEach(configuration.options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
                .colorScheme(.dark)
                .frame(width: Metrics.Layout.pickerWidth, alignment: .leading)

                if selectedOption == Strings.Common.other {
                    TextField(Strings.AuditReason.reason, text: $detailText, axis: .vertical)
                        .textFieldStyle(.appGlassMultiline)
                        .foregroundStyle(.primary)
                        .lineLimit(3...6)
                        .transition(.opacity)
                }
            }

            HStack {
                if !configuration.isRequired {
                    Button(Strings.AuditReason.clearReason) {
                        onSave("")
                        onClose()
                    }
                    .buttonStyle(.secondaryAction)
                }

                Spacer()

                Button(Strings.Common.cancel, action: onClose)
                    .buttonStyle(.secondaryAction)

                Button(Strings.AuditReason.saveReason) {
                    onSave(reasonToSave)
                    onClose()
                }
                .buttonStyle(.primaryAction)
                .disabled(!canSave)
            }
        }
        .padding(Spacing.large)
        .frame(width: Metrics.Layout.reasonSheetWidth)
        .glassySurface()
        .animation(.easeInOut, value: selectedOption)
    }

    private var header: some View {
        HStack {
            Text(configuration.title)
                .font(Fonts.sectionTitle)

            Spacer()

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.iconAction)
        }
    }

    private var reasonToSave: String {
        if configuration.textOnly || selectedOption == Strings.Common.other {
            return detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return selectedOption
    }

    private var canSave: Bool {
        !configuration.isRequired || !reasonToSave.isEmpty
    }
}
