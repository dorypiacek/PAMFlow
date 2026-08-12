//
//  ProjectSetupView.swift
//  PAMFlow
//
//  Created by Dory on 06/06/2026.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Screen for creating a PAMFlow project from one recorder or camera data source.
struct ProjectSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator

    @State private var model: ProjectSetupModel
    @State private var isShowingManualMetadata = false
    @State private var csvTable: BRUVMetadataTable?
    @State private var selectedMetadataOpcode = ""

    init(
        module: WorkflowModule,
        projectFileService: ProjectFileServicing,
        fileSelectionService: FileSelecting
    ) {
        _model = State(
            initialValue: ProjectSetupModel(
                module: module,
                projectFileService: projectFileService,
                fileSelectionService: fileSelectionService
            )
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
            loadCachedMetadataTable()
        }
        .sheet(isPresented: $isShowingManualMetadata) {
            BRUVMetadataManualEntrySheet(
                module: model.module,
                opcode: $model.metadataOpcode,
                date: $model.metadataDate,
                dateRetrieved: $model.metadataDateRetrieved,
                location: $model.metadataLocation,
                depth: $model.metadataDepth,
                bottomType: $model.metadataBottomType,
                waterTemperature: $model.metadataWaterTemperature,
                onClose: { isShowingManualMetadata = false }
            )
        }
    }
    
    private var projectNameField: some View {
        TextField(ProjectSetupStrings.projectNamePlaceholder, text: $model.projectName)
            .textFieldStyle(.roundedBorder)
            .frame(width: Metrics.Layout.pickerWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inputSourcePicker: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Button {
                model.selectInputSource()
            } label: {
                Label(ProjectSetupStrings.inputFolderButton, systemImage: Icons.folder)
            }
            .buttonStyle(.secondaryAction)

            HStack {
                if let selectedInputSource = model.selectedInputSource {
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

            Text(model.inputSelectionGuidance)
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
        .disabled(!model.canCreateProject)
    }

    @ViewBuilder
    private var bruvMetadataSection: some View {
        if model.module.usesProjectMetadata {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                HStack(spacing: Spacing.small) {
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        Text(String(format: ProjectSetupStrings.metadataTitleFormat, model.module.title))
                            .font(Fonts.subtitle)
                        if let csvTable {
                            Text(csvTable.fileName)
                                .font(Fonts.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    
                    Spacer()

                    Button {
                        uploadMetadataTable()
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

                if let csvTable {
                    Picker(ProjectSetupStrings.opcode, selection: $selectedMetadataOpcode) {
                        Text(ProjectSetupStrings.selectOpcode).tag("")
                        ForEach(csvTable.rows.compactMap(\.opcode), id: \.self) { opcode in
                            Text(opcode).tag(opcode)
                        }
                    }
                    .onChange(of: selectedMetadataOpcode) {
                        applyCSVMetadata(opcode: selectedMetadataOpcode)
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
            metadataValue(ProjectSetupStrings.opcode, model.metadataOpcode)
            metadataValue(model.module == .pamAudio ? ProjectSetupStrings.dateDeployed : ProjectSetupStrings.date, model.metadataDate)
            if model.module == .pamAudio {
                metadataValue(ProjectSetupStrings.dateRetrieved, model.metadataDateRetrieved)
            }
            metadataValue(ProjectSetupStrings.location, model.metadataLocation)
            metadataValue(ProjectSetupStrings.depth, model.metadataDepth)
            metadataValue(ProjectSetupStrings.bottomType, model.metadataBottomType)
            if model.module != .pamAudio {
                metadataValue(ProjectSetupStrings.waterTemperature, model.metadataWaterTemperature)
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

    private func uploadMetadataTable() {
        let panel = NSOpenPanel()
        panel.title = String(format: ProjectSetupStrings.uploadMetadataCSVTitleFormat, model.module.title)
        panel.message = metadataUploadMessage
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: metadataCacheBookmarkKey)
            try loadMetadataTable(from: url)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func loadCachedMetadataTable() {
        guard model.module.usesProjectMetadata,
              let bookmark = UserDefaults.standard.data(forKey: metadataCacheBookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        try? loadMetadataTable(from: url)
    }

    private func loadMetadataTable(from url: URL) throws {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let table = try BRUVMetadataTable(url: url)
        csvTable = table
        selectedMetadataOpcode = ""
        model.errorMessage = nil
    }

    private func applyCSVMetadata(opcode: String) {
        guard let row = csvTable?.rows.first(where: { $0.opcode == opcode }) else { return }
        model.metadataOpcode = row.opcode ?? ""
        model.metadataDate = row.date ?? ""
        model.metadataDateRetrieved = row.dateRetrieved ?? ""
        model.metadataLocation = row.location ?? ""
        model.metadataDepth = row.depth ?? ""
        model.metadataBottomType = row.bottomType ?? ""
        model.metadataWaterTemperature = row.waterTemperature ?? ""
    }

    @ViewBuilder
    private var feedbackText: some View {
        if let project = model.createdProject {
            Text("\(ProjectSetupStrings.createdPrefix) \(project.name)")
                .foregroundStyle(AppColors.success)
        }

        if let error = model.errorMessage {
            Text(error)
                .foregroundStyle(AppColors.error)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Metrics.Layout.compactContentWidth)
        }
    }

    private func createProject() {
        guard let project = model.createProject() else { return }

        modelContext.insert(project)
        do {
            try modelContext.save()
            appCoordinator.scanProject(project)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private var metadataUploadMessage: String {
        if model.module == .pamAudio {
            ProjectSetupStrings.pamMetadataUploadMessage
        } else {
            ProjectSetupStrings.visualMetadataUploadMessage
        }
    }

    private var metadataCacheBookmarkKey: String {
        "pamflow.\(model.module.id).metadata.csv.bookmark"
    }
}

private typealias ProjectSetupStrings = Strings.ProjectSetup

private struct BRUVMetadataManualEntrySheet: View {
    let module: WorkflowModule
    @Binding var opcode: String
    @Binding var date: String
    @Binding var dateRetrieved: String
    @Binding var location: String
    @Binding var depth: String
    @Binding var bottomType: String
    @Binding var waterTemperature: String

    let onClose: () -> Void
    @State private var selectedDate = Date()
    @State private var selectedRetrievedDate = Date()

    private var canClose: Bool {
        !opcode.trimmed.isEmpty &&
            !date.trimmed.isEmpty &&
            !location.trimmed.isEmpty &&
            !depth.trimmed.isEmpty &&
            (module != .pamAudio || !dateRetrieved.trimmed.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            HStack {
                Text(String(format: ProjectSetupStrings.metadataTitleFormat, module.title))
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
                field(ProjectSetupStrings.opcode, text: $opcode)
                DatePicker(
                    module == .pamAudio ? ProjectSetupStrings.dateDeployed : ProjectSetupStrings.date,
                    selection: Binding(
                        get: { selectedDate },
                        set: { newValue in
                            selectedDate = newValue
                            date = Self.dateFormatter.string(from: newValue)
                        }
                    ),
                    displayedComponents: [.date]
                )
                if module == .pamAudio {
                    DatePicker(
                        ProjectSetupStrings.dateRetrieved,
                        selection: Binding(
                            get: { selectedRetrievedDate },
                            set: { newValue in
                                selectedRetrievedDate = newValue
                                dateRetrieved = Self.dateFormatter.string(from: newValue)
                            }
                        ),
                        displayedComponents: [.date]
                    )
                }
                field(ProjectSetupStrings.location, text: $location)
                field(ProjectSetupStrings.depth, text: $depth)
                field(ProjectSetupStrings.bottomType, text: $bottomType)
                if module != .pamAudio {
                    field(ProjectSetupStrings.waterTemperature, text: $waterTemperature)
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
            selectedDate = Self.dateFormatter.date(from: date) ?? Date()
            if date.trimmed.isEmpty {
                date = Self.dateFormatter.string(from: selectedDate)
            }
            selectedRetrievedDate = Self.dateFormatter.date(from: dateRetrieved) ?? Date()
            if module == .pamAudio && dateRetrieved.trimmed.isEmpty {
                dateRetrieved = Self.dateFormatter.string(from: selectedRetrievedDate)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(title)
                .font(Fonts.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct BRUVMetadataTable {
    let fileName: String
    let rows: [BRUVMetadataRow]

    init(url: URL) throws {
        fileName = url.lastPathComponent
        let text = try String(contentsOf: url, encoding: .utf8)
        let parsedRows = Self.parseCSV(text)
        guard let header = parsedRows.first else {
            rows = []
            return
        }

        let mapping = BRUVMetadataColumnMapping(header: header)
        rows = parsedRows.dropFirst().compactMap { values in
            BRUVMetadataRow(
                opcode: mapping.value(in: values, for: \.opcode),
                date: mapping.value(in: values, for: \.date),
                dateRetrieved: mapping.value(in: values, for: \.dateRetrieved),
                location: mapping.value(in: values, for: \.location),
                depth: mapping.value(in: values, for: \.depth),
                bottomType: mapping.value(in: values, for: \.bottomType),
                waterTemperature: mapping.value(in: values, for: \.waterTemperature)
            )
        }
        .filter { $0.opcode?.isEmpty == false }
    }

    private static func parseCSV(_ text: String) -> [[String]] {
        text
            .split(whereSeparator: \.isNewline)
            .map { parseCSVLine(String($0)) }
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var values: [String] = []
        var current = ""
        var isQuoted = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                isQuoted.toggle()
            } else if character == "," && !isQuoted {
                values.append(current.trimmed)
                current = ""
            } else {
                current.append(character)
            }
        }

        values.append(current.trimmed)
        return values
    }
}

private struct BRUVMetadataRow {
    let opcode: String?
    let date: String?
    let dateRetrieved: String?
    let location: String?
    let depth: String?
    let bottomType: String?
    let waterTemperature: String?
}

private struct BRUVMetadataColumnMapping {
    let opcode: Int?
    let date: Int?
    let dateRetrieved: Int?
    let location: Int?
    let depth: Int?
    let bottomType: Int?
    let waterTemperature: Int?

    init(header: [String]) {
        opcode = Self.index(in: header, matching: ["opcode", "op code", "operation code"])
        date = Self.index(in: header, matching: ["date deployed", "deployment date", "deploy date", "sample date", "date"])
        dateRetrieved = Self.index(in: header, matching: ["date retrieved", "retrieval date", "retrieve date", "recovery date", "date recovered"])
        location = Self.index(in: header, matching: ["location", "site", "station"])
        depth = Self.index(in: header, matching: ["depth", "water depth"])
        bottomType = Self.index(in: header, matching: ["bottom type", "substrate", "habitat"])
        waterTemperature = Self.index(in: header, matching: ["water temperature", "temperature", "temp"])
    }

    func value(in values: [String], for keyPath: KeyPath<BRUVMetadataColumnMapping, Int?>) -> String? {
        guard let index = self[keyPath: keyPath], values.indices.contains(index) else { return nil }
        return values[index].trimmed
    }

    private static func index(in header: [String], matching candidates: [String]) -> Int? {
        header.firstIndex { rawName in
            let normalized = rawName.normalizedFieldName
            return candidates.contains { normalized.contains($0.normalizedFieldName) }
        }
    }
}
