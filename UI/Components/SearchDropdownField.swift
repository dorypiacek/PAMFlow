//
//  SearchDropdownField.swift
//  PAMFlow
//
//  Created by Dory on 16/09/2026.
//

import SwiftUI

/// Search field that presents matching suggestions in a popover without changing parent layout.
public struct SearchDropdownField<Item: Identifiable>: View {
    @Binding private var text: String
    @FocusState private var isFocused: Bool

    private let placeholder: String
    private let items: [Item]
    private let itemTitle: (Item) -> String
    private let isEnabled: Bool
    private let visibleRowCount: Int
    private let onSelect: (Item) -> Void

    @State private var highlightedIndex = 0
    @State private var visibleStartIndex = 0
    @State private var isShowingSuggestions = false

    public init(
        text: Binding<String>,
        placeholder: String,
        items: [Item],
        itemTitle: @escaping (Item) -> String,
        isEnabled: Bool = true,
        visibleRowCount: Int = Metrics.Layout.searchDropdownVisibleRows,
        onSelect: @escaping (Item) -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.items = items
        self.itemTitle = itemTitle
        self.isEnabled = isEnabled
        self.visibleRowCount = visibleRowCount
        self.onSelect = onSelect
    }

    public var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.appGlass)
            .disabled(!isEnabled)
            .focused($isFocused)
            .onChange(of: text) {
                highlightedIndex = 0
                visibleStartIndex = 0
                updateSuggestionVisibility()
            }
            .onChange(of: isFocused) {
                updateSuggestionVisibility()
            }
            .onKeyPress(.downArrow) {
                moveHighlight(by: 1)
                return .handled
            }
            .onKeyPress(.upArrow) {
                moveHighlight(by: -1)
                return .handled
            }
            .onKeyPress(.return) {
                selectHighlightedItem()
                return .handled
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.Layout.speciesSearchFieldHeight + Spacing.medium)
            .popover(isPresented: $isShowingSuggestions, arrowEdge: .bottom) {
                dropdown
                    .frame(width: Metrics.Layout.speciesSearchPopoverWidth)
                    .padding(Spacing.xSmall)
                    .presentationCompactAdaptation(.popover)
            }
    }

    private var shouldShowSuggestions: Bool {
        isFocused
            && isEnabled
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !filteredItems.isEmpty
    }

    private var filteredItems: [Item] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return items
            .filter { itemTitle($0).localizedCaseInsensitiveContains(query) }
            .prefix(50)
            .map { $0 }
    }

    private var dropdown: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                        Button {
                            select(item)
                        } label: {
                            Text(itemTitle(item))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Spacing.medium)
                                .padding(.vertical, Spacing.small)
                                .background {
                                    if index == highlightedIndex {
                                        RoundedRectangle(
                                            cornerRadius: Metrics.Layout.rowCornerRadius * 2,
                                            style: .continuous
                                        )
                                        .fill(AppColors.accent.opacity(Metrics.Opacity.hoverHighlight))
                                        .padding(.horizontal, Spacing.xSmall)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
            }
            .frame(height: dropdownHeight)
            .transition(.opacity)
            .onChange(of: visibleStartIndex) {
                withAnimation {
                    proxy.scrollTo(visibleStartIndex, anchor: .top)
                }
            }
            .onChange(of: filteredItems.count) {
                withAnimation {
                    highlightedIndex = min(highlightedIndex, max(filteredItems.count - 1, 0))
                    visibleStartIndex = min(visibleStartIndex, max(filteredItems.count - visibleRowCount, 0))
                }
            }
        }
    }

    private var dropdownHeight: CGFloat {
        let visibleCount = min(filteredItems.count, visibleRowCount)
        return Metrics.Layout.searchDropdownRowHeight * CGFloat(visibleCount)
    }

    private func updateSuggestionVisibility() {
        isShowingSuggestions = shouldShowSuggestions
    }

    private func moveHighlight(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        isShowingSuggestions = shouldShowSuggestions
        highlightedIndex = min(max(highlightedIndex + offset, 0), filteredItems.count - 1)
        updateVisibleWindow()
    }

    private func selectHighlightedItem() {
        guard isShowingSuggestions,
              filteredItems.indices.contains(highlightedIndex) else { return }
        select(filteredItems[highlightedIndex])
    }

    private func select(_ item: Item) {
        text = itemTitle(item)
        highlightedIndex = 0
        isShowingSuggestions = false
        isFocused = false
        onSelect(item)
    }

    private func updateVisibleWindow() {
        if highlightedIndex < visibleStartIndex {
            visibleStartIndex = highlightedIndex
        } else if highlightedIndex >= visibleStartIndex + visibleRowCount {
            visibleStartIndex = highlightedIndex - visibleRowCount + 1
        }
    }
}
