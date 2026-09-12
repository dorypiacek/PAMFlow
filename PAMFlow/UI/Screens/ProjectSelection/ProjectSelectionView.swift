//
//  ProjectSelectionView.swift
//  PAMFlow
//
//  Created by Dory on 08/06/2026.
//

import SwiftData
import SwiftUI

/// Renders saved projects and forwards open/delete actions through project-selection state.
struct ProjectSelectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppCoordinator.self) private var appCoordinator
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var errorMessage: String?
    @State private var projectIDPendingDeletion: UUID?
    @State private var selectedProjectGroup: ProjectGroup = .inProgress
    @State private var searchText = ""

    private var presentation: ProjectSelectionViewModel {
        ProjectSelectionViewModel(
            projects: projects,
            selectedGroup: selectedProjectGroup,
            searchText: searchText,
            moduleCatalog: appCoordinator.moduleCatalog,
            auditProgress: { project in
                ProjectSelectionViewModel.auditProgress(
                    for: project,
                    modelContext: modelContext,
                    projectScanService: appCoordinator.dependencies.projectScanService
                )
            },
            summary: { project in
                ProjectSelectionViewModel.summary(
                    for: project,
                    projectScanService: appCoordinator.dependencies.projectScanService
                )
            },
            folderExists: ProjectSelectionViewModel.projectFolderExists(_:)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()

            VStack(alignment: .leading, spacing: Spacing.large) {
                header

                HStack(alignment: .top, spacing: Spacing.large) {
                    sidebar

                    if projects.isEmpty {
                        emptyProjectCard
                    } else {
                        projectList
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(AppColors.error)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, Spacing.large)
            .padding(.top, Spacing.large)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppColors.background)
        .task {
            ProjectSelectionViewModel.preheatLatestProjectPreviews(
                projects: projects,
                modelContext: modelContext,
                dependencies: appCoordinator.dependencies
            )
        }
        .alert(
            Strings.ProjectSelection.deleteConfirmationTitle,
            isPresented: Binding(
                get: { projectIDPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        projectIDPendingDeletion = nil
                    }
                }
            )
        ) {
            Button(Strings.ProjectSelection.deleteConfirmationButton, role: .destructive) {
                confirmProjectDeletion()
            }

            Button(Strings.ProjectSelection.deleteConfirmationCancelButton, role: .cancel) {
                projectIDPendingDeletion = nil
            }
        } message: {
            Text(Strings.ProjectSelection.deleteConfirmationMessage)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(Strings.ProjectSelection.title)
                    .font(Fonts.screenTitle)

                Text(Strings.ProjectSelection.subtitle)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appCoordinator.openDataTypeSelection()
            } label: {
                Label(Strings.ProjectSelection.newProjectButton, systemImage: Icons.add)
                    .font(Fonts.body.weight(.semibold))
                    .frame(height: Metrics.Layout.auditControlHeight)
                    .padding(.horizontal, Spacing.medium)
            }
            .buttonStyle(.primaryAction)
            .clipShape(.capsule)
        }
    }

    private var emptyProjectCard: some View {
        VStack(alignment: .center, spacing: Spacing.medium) {
            Text(Strings.ProjectSelection.emptyTitle)
                .font(Fonts.sectionTitle)

            Text(Strings.ProjectSelection.emptySubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(Strings.ProjectSelection.newProjectButton) {
                appCoordinator.openDataTypeSelection()
            }
            .buttonStyle(.primaryAction)
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.projectSelectionCardHeight, alignment: .center)
        .glassySurface()
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.medium) {
                if presentation.filteredProjects.isEmpty {
                    Text(Strings.ProjectSelection.noMatchingProjects)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.projectSelectionCardHeight)
                        .glassySurface()
                } else {
                    ForEach(presentation.filteredProjects) { project in
                        projectRow(presentation.row(for: project))
                    }
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            TextField(Strings.ProjectSelection.searchPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)

            ForEach(ProjectGroup.allCases, id: \.self) { group in
                sidebarGroupButton(group)
            }
        }
        .padding(Spacing.large)
        .frame(
            width: 240,
            height: Metrics.Layout.projectSelectionCardHeight,
            alignment: .topLeading
        )
        .glassySurface()
    }

    @ViewBuilder
    private func sidebarGroupButton(_ group: ProjectGroup) -> some View {
        let isSelected = selectedProjectGroup == group
        let label = HStack {
            Text(group.title)
            Spacer()
            Text("\(presentation.count(for: group))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(Fonts.body.weight(.semibold))
        .frame(height: Metrics.Layout.auditControlHeight)
        .padding(.horizontal, Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)

        if isSelected {
            Button {
                selectedProjectGroup = group
            } label: {
                label
            }
            .buttonStyle(.primaryAction)
            .controlSize(.regular)
            .clipShape(.capsule)
        } else {
            Button {
                selectedProjectGroup = group
            } label: {
                label
            }
            .buttonStyle(.prominentSecondaryAction)
            .controlSize(.regular)
            .clipShape(.capsule)
        }
    }

    private func projectRow(_ row: ProjectSelectionRowViewModel) -> some View {
        HStack(alignment: .center, spacing: Spacing.xLarge) {
                Image(systemName: row.moduleIconName)
                    .font(.system(size: Metrics.Layout.projectCardModuleIconSize, weight: .semibold))
                    .frame(
                        width: Metrics.Layout.projectCardModuleIconSize,
                        height: Metrics.Layout.projectCardModuleIconSize,
                        alignment: .center
                    )
                    .foregroundStyle(.secondary)
                    .help(row.moduleTitle)

                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(row.project.name)
                        .font(Fonts.sectionTitle)

                    Text(row.statusTitle)
                        .foregroundStyle(row.statusColor)

                    Text(row.lastCompletedText)
                        .foregroundStyle(.secondary)

                    HStack(spacing: Spacing.medium) {
                        if let recorderText = row.recorderText {
                            Text(recorderText)
                        }

                        if let lastOpenedText = row.lastOpenedText {
                            Text(lastOpenedText)
                        }
                    }
                    .font(Fonts.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: Spacing.small) {
                    Button(row.primaryActionTitle) {
                        openProject(row.project, folderExists: row.folderExists)
                    }
                    .buttonStyle(.primaryAction)

                    Button(Strings.ProjectSelection.deleteButton, role: .destructive) {
                        projectIDPendingDeletion = row.project.id
                    }
                    .buttonStyle(.secondaryAction)
                }
            }
            .contentShape(Rectangle())
        .padding(Spacing.large)
        .padding(.leading, Spacing.small)
        .frame(maxWidth: .infinity, minHeight: Metrics.Layout.projectSelectionCardHeight, alignment: .leading)
        .glassySurface()
        .onTapGesture {
            openProject(row.project, folderExists: row.folderExists)
        }
    }

    private func openProject(_ project: Project, folderExists: Bool) {
        presentation.openProject(project, folderExists: folderExists, coordinator: appCoordinator)
    }

    private func confirmProjectDeletion() {
        guard
            let projectIDPendingDeletion,
            let project = projects.first(where: { $0.id == projectIDPendingDeletion })
        else {
            self.projectIDPendingDeletion = nil
            return
        }

        errorMessage = presentation.deleteProject(
            project,
            modelContext: modelContext,
            dependencies: appCoordinator.dependencies
        )
        self.projectIDPendingDeletion = nil
    }
}
