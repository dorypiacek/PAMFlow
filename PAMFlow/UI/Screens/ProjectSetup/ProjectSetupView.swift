//
//  ProjectSetupView.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import SwiftData
import SwiftUI

/// Renders module-configured project setup and forwards creation events to its ViewModel.
struct ProjectSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    @State private var viewModel: BaseProjectSetupViewModel
    @State private var isShowingManualMetadata = false

    init(
        viewModel: BaseProjectSetupViewModel
    ) {
        _viewModel = State(
            initialValue: viewModel
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            Spacer()
            
            VStack(alignment: .leading, spacing: Spacing.large) {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(ProjectSetupStrings.title)
                        .font(Fonts.screenTitle)

                    Text(ProjectSetupStrings.subtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                inputSourcePicker

                projectNameField
                
                Divider()

                bruvMetadataSection

                createButton

                feedbackText
            }
            .padding(Spacing.large)
            .frame(maxWidth: Metrics.Layout.readableTextWidth, alignment: .leading)
            .glassySurface()
            .padding(Spacing.large)

            Spacer()
        }
        .background(AppColors.background)
        .onAppear {
            viewModel.loadCachedMetadataTable()
        }
        .sheet(isPresented: $isShowingManualMetadata) {
            ProjectMetadataManualEntrySheet(
                configuration: viewModel.configuration,
                values: $viewModel.metadataValues,
                onClose: { isShowingManualMetadata = false }
            )
        }
    }
    
    private var projectNameField: some View {
        TextField(ProjectSetupStrings.projectNamePlaceholder, text: $viewModel.projectName)
            .textFieldStyle(.roundedBorder)
            .frame(width: Metrics.Layout.pickerWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputSourcePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Button {
                viewModel.selectInputSource()
            } label: {
                Label(ProjectSetupStrings.inputFolderButton, systemImage: Icons.folder)
            }
            .buttonStyle(.secondaryAction)

            HStack {
                if let selectedInputSource = viewModel.selectedInputSource {
                    ClickablePathText(path: selectedInputSource.displayText)
                        .font(Fonts.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: Metrics.Layout.compactContentWidth, alignment: .leading)
                    
                } else {
                    Text(ProjectSetupStrings.singleRecorderHint)
                        .font(Fonts.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: Metrics.Layout.compactContentWidth, alignment: .leading)
                }
                
                Spacer()
            }

            Text(viewModel.inputSelectionGuidance)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: Metrics.Layout.compactContentWidth, alignment: .leading)
        }
    }

    private var createButton: some View {
        Button(ProjectSetupStrings.createButton) {
            createProject()
        }
        .buttonStyle(.primaryAction)
        .disabled(!viewModel.canCreateProject)
    }

    @ViewBuilder
    private var bruvMetadataSection: some View {
        if viewModel.configuration.usesProjectMetadata {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                HStack(spacing: Spacing.small) {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(String(format: ProjectSetupStrings.metadataTitleFormat, viewModel.configuration.module.name))
                            .font(Fonts.subtitle)
                        if let metadataFileName = viewModel.metadataFileName {
                            Text(metadataFileName)
                                .font(Fonts.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    
                    Spacer()

                    Button {
                        viewModel.uploadMetadataTable()
                    } label: {
                        Label(ProjectSetupStrings.uploadCSV, systemImage: Icons.upload)
                    }
                    .buttonStyle(.secondaryAction)
                    .frame(height: Metrics.Layout.modalCloseButtonSize)

                    Button(ProjectSetupStrings.enterManually) {
                        isShowingManualMetadata = true
                    }
                    .buttonStyle(.secondaryAction)
                    .frame(height: Metrics.Layout.modalCloseButtonSize)
                }

                if viewModel.showsMetadataSelection {
                    Picker(viewModel.metadataSelectionTitle, selection: $viewModel.selectedMetadataRowID) {
                        Text(ProjectSetupStrings.selectOpcode).tag("")
                        ForEach(viewModel.metadataSelectionOptions, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                    .onChange(of: viewModel.selectedMetadataRowID) {
                        viewModel.applySelectedMetadataRow()
                    }
                }

                metadataSummary
            }
        }
    }

    private var metadataSummary: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160), spacing: Spacing.small)],
            alignment: .leading,
            spacing: Spacing.small
        ) {
            ForEach(viewModel.configuration.requiredMetadataFields, id: \.id) { field in
                metadataValue(field.title, viewModel.metadataValue(for: field.id))
            }
        }
    }

    private func metadataValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? Strings.Common.unknown : value)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var feedbackText: some View {
        if let project = viewModel.createdProject {
            Text("\(ProjectSetupStrings.createdPrefix) \(project.name)")
                .foregroundStyle(AppColors.success)
        }

        if let error = viewModel.errorMessage {
            Text(error)
                .foregroundStyle(AppColors.error)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Metrics.Layout.compactContentWidth)
        }
    }

    private func createProject() {
        guard let project = viewModel.createAndSaveProject(modelContext: modelContext) else { return }
        appCoordinator.goToNextStep(for: project)
    }

}

private typealias ProjectSetupStrings = Strings.ProjectSetup

private struct ProjectMetadataManualEntrySheet: View {
    let configuration: ProjectSetupConfiguration
    @Binding var values: ProjectMetadataValues

    let onClose: () -> Void
    @State private var selectedDates: [String: Date] = [:]

    private var canClose: Bool {
        configuration.isMetadataComplete(values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                Text(String(format: ProjectSetupStrings.metadataTitleFormat, configuration.module.name))
                    .font(Fonts.sectionTitle)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.iconAction)
                .help(Strings.Common.close)
            }

            Group {
                ForEach(configuration.requiredMetadataFields, id: \.id) { field in
                    switch field.valueType {
                    case .string:
                        textField(field)
                    case .number:
                        numberField(field)
                    case .date:
                        dateField(field)
                    }
                }
            }

            HStack {
                Spacer()
                Button(ProjectSetupStrings.done) {
                    onClose()
                }
                .buttonStyle(.primaryAction)
                .disabled(!canClose)
            }
        }
        .padding(Spacing.large)
        .frame(width: Metrics.Layout.settingsWidth)
        .glassySurface()
        .padding(Spacing.large)
        .onAppear {
            for field in configuration.requiredMetadataFields where field.valueType == .date {
                let selectedDate = Self.dateFormatter.date(from: values.value(for: field.id)) ?? Date()
                selectedDates[field.id] = selectedDate
                if values.value(for: field.id).trimmed.isEmpty {
                    values.setValue(Self.dateFormatter.string(from: selectedDate), for: field.id)
                }
            }
        }
    }

    private func textField(_ field: ProjectMetadataField) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(field.title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            TextField(field.title, text: binding(for: field.id))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func numberField(_ field: ProjectMetadataField) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(field.title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            TextField(field.title, text: binding(for: field.id))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func dateField(_ field: ProjectMetadataField) -> some View {
        DatePicker(
            field.title,
            selection: dateBinding(for: field.id),
            displayedComponents: [.date]
        )
    }

    private func binding(for fieldID: String) -> Binding<String> {
        Binding(
            get: { values.value(for: fieldID) },
            set: { values.setValue($0, for: fieldID) }
        )
    }

    private func dateBinding(for fieldID: String) -> Binding<Date> {
        Binding(
            get: { selectedDates[fieldID] ?? Self.dateFormatter.date(from: values.value(for: fieldID)) ?? Date() },
            set: { newValue in
                selectedDates[fieldID] = newValue
                values.setValue(Self.dateFormatter.string(from: newValue), for: fieldID)
            }
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
