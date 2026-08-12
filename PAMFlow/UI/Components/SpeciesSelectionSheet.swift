//
//  SpeciesSelectionSheet.swift
//  PAMFlow
//
//  Created by Dory on 18/06/2026.
//

import SwiftUI

/// Optional species metadata attached to one reviewed detection.
struct SpeciesSelection: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var family: String?
    var genus: String?
    var species: String?
    var fullName: String
}

/// Editable species state for one SharkTrack individual in a reviewed frame.
struct SpeciesAssignmentDraft: Equatable, Identifiable {
    let id: String
    let trackID: Int?
    let confidence: Double?
    var selection: SpeciesSelection?
    var isRemoved: Bool
}

/// Edits one species assignment per SharkTrack individual in the current frame.
struct SpeciesSelectionSheet: View {
    let taxa: [SpeciesTaxon]
    let onSave: ([SpeciesAssignmentDraft]) -> Void
    let onClose: () -> Void

    @State private var drafts: [SpeciesAssignmentDraft]
    @State private var showsDiscardAlert = false
    private let initialDrafts: [SpeciesAssignmentDraft]

    init(
        taxa: [SpeciesTaxon],
        drafts: [SpeciesAssignmentDraft],
        onSave: @escaping ([SpeciesAssignmentDraft]) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.taxa = taxa
        self.onSave = onSave
        self.onClose = onClose
        initialDrafts = drafts
        _drafts = State(initialValue: drafts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            header
            VStack(alignment: .leading, spacing: Spacing.small + Spacing.xSmall) {
                tableHeader
                ForEach(drafts.indices, id: \.self) { index in
                    SpeciesAssignmentRow(draft: $drafts[index], taxa: taxa)
                        .zIndex(Double(drafts.count - index))
                }
            }
            Button(Strings.SpeciesSelection.save) {
                onSave(drafts)
                onClose()
            }
            .buttonStyle(.primaryAction)
        }
        .padding(Spacing.large)
        .frame(width: min(Metrics.Layout.wideContentWidth, 980))
        .glassySurface()
        .alert(Strings.SpeciesSelection.discardTitle, isPresented: $showsDiscardAlert) {
            Button(Strings.SpeciesSelection.discardChanges, role: .destructive, action: onClose)
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: {
            Text(Strings.SpeciesSelection.discardMessage)
        }
    }

    private var header: some View {
        HStack {
            Text(Strings.SpeciesSelection.title).font(Fonts.sectionTitle)
            Spacer()
            Button {
                drafts == initialDrafts ? onClose() : (showsDiscardAlert = true)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.iconAction)
        }
    }

    private var tableHeader: some View {
        HStack(spacing: Spacing.medium) {
            Text(Strings.ManualAudit.trackID)
                .frame(width: Metrics.Layout.speciesTrackColumnWidth, alignment: .leading)
            Text(Strings.ManualAudit.confidence)
                .frame(width: Metrics.Layout.speciesConfidenceColumnWidth, alignment: .leading)
            Text(Strings.SpeciesSelection.species)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear
                .frame(width: Metrics.Layout.speciesActionColumnWidth)
        }
        .font(Fonts.caption)
        .foregroundStyle(.secondary)
    }
}

/// A searchable, reversible assignment row for one tracked individual.
private struct SpeciesAssignmentRow: View {
    @Binding var draft: SpeciesAssignmentDraft
    let taxa: [SpeciesTaxon]

    @State private var searchText = ""
    @State private var hoveredTaxonID: String?
    @State private var isShowingTaxonomy = false
    @State private var family: String?
    @State private var genus: String?
    @State private var species: String?

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            idCell
            confidenceCell
            speciesField
            taxonomyButton
        }
        .onAppear { loadSelection() }
        .popover(isPresented: $isShowingTaxonomy) {
            taxonomyEditor
                .padding(Spacing.medium)
                .frame(width: Metrics.Layout.pickerWidth)
        }
    }

    private var idCell: some View {
        Text(draft.trackID.map(String.init) ?? Strings.Common.unknown)
            .monospacedDigit()
        .frame(width: Metrics.Layout.speciesTrackColumnWidth, alignment: .leading)
    }

    private var confidenceCell: some View {
        Text(draft.confidence.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? Strings.Common.unknown)
            .monospacedDigit()
            .frame(width: Metrics.Layout.speciesConfidenceColumnWidth, alignment: .leading)
    }

    private var speciesField: some View {
        ZStack(alignment: .topLeading) {
            TextField(Strings.SpeciesSelection.searchPlaceholder, text: $searchText)
                .textFieldStyle(.appGlass)
                .disabled(draft.isRemoved)
                .frame(maxWidth: .infinity)

            if isSearching, !searchResults.isEmpty {
                searchResultsMenu
                    .offset(y: Metrics.Layout.speciesSearchFieldHeight + Spacing.xSmall)
                    .zIndex(10)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.speciesSearchFieldHeight, alignment: .topLeading)
        .zIndex(10)
    }

    private var taxonomyButton: some View {
        Button { isShowingTaxonomy = true } label: { Image(systemName: "plus") }
            .buttonStyle(.iconAction)
            .disabled(draft.isRemoved)
            .frame(width: Metrics.Layout.speciesActionColumnWidth, alignment: .trailing)
    }

    private var searchResultsMenu: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(searchResults) { taxon in
                    Button { select(taxon) } label: {
                        Text(taxon.displayName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Spacing.medium)
                            .padding(.vertical, Spacing.small)
                            .background(hoveredTaxonID == taxon.id
                                ? AppColors.accent.opacity(Metrics.Opacity.hoverHighlight)
                                : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredTaxonID = $0 ? taxon.id : nil }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: max(Metrics.Layout.speciesSearchResultsHeight, 280))
        .glassySurface()
    }

    private var taxonomyEditor: some View {
        VStack(spacing: Spacing.small) {
            Picker(Strings.SpeciesSelection.family, selection: $family) {
                Text(Strings.Common.unknown).tag(String?.none)
                ForEach(families, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .onChange(of: family) { genus = nil; species = nil }
            Picker(Strings.SpeciesSelection.genus, selection: $genus) {
                Text(Strings.Common.unknown).tag(String?.none)
                ForEach(genera, id: \.self) { Text($0).tag(String?.some($0)) }
            }
            .disabled(family == nil)
            .onChange(of: genus) { species = nil }
            Picker(Strings.SpeciesSelection.species, selection: $species) {
                Text(Strings.Common.unknown).tag(String?.none)
                ForEach(speciesOptions) { Text($0.displayName).tag(String?.some($0.species)) }
            }
            .disabled(genus == nil)
            .onChange(of: species) { if let selectedTaxon { select(selectedTaxon) } }
        }
    }

    private var isSearching: Bool {
        !draft.isRemoved && !searchText.isEmpty && searchText != draft.selection?.fullName
    }
    private var searchResults: [SpeciesTaxon] { taxa.filter { $0.matches(searchText) }.prefix(20).map { $0 } }
    private var families: [String] { taxa.map(\.family).uniquedForDisplay() }
    private var genera: [String] { taxa.filter { $0.family == family }.map(\.genus).uniquedForDisplay() }
    private var speciesOptions: [SpeciesTaxon] { taxa.filter { $0.family == family && $0.genus == genus } }
    private var selectedTaxon: SpeciesTaxon? { speciesOptions.first { $0.species == species } }

    private func loadSelection() {
        searchText = draft.isRemoved ? Strings.SpeciesSelection.noDetection : draft.selection?.fullName ?? ""
        family = draft.selection?.family
        genus = draft.selection?.genus
        species = draft.selection?.species
    }

    private func select(_ taxon: SpeciesTaxon) {
        draft.selection = SpeciesSelection(
            id: draft.selection?.id ?? UUID().uuidString,
            family: taxon.family,
            genus: taxon.genus,
            species: taxon.species,
            fullName: taxon.displayName
        )
        searchText = taxon.displayName
        family = taxon.family
        genus = taxon.genus
        species = taxon.species
        isShowingTaxonomy = false
    }
}
