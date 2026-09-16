# PAMFlow Architecture

PAMFlow is organized as a modular macOS app. The app target is intentionally thin: it owns launch, persistence setup, dependency composition, and the list of feature modules compiled into a build. Shared behavior lives in `Core` and `UI`, while workflow-specific behavior lives in modules under `Modules/`.

This structure keeps PAM, BRUV, and RUV workflows separable enough to become independently testable Swift packages, while still sharing the generic project shell, persistence, scanning, review, and export UI patterns.

## Package Boundaries

The dependency direction is one-way:

```text
App
  -> Core
  -> UI
  -> Modules/PAM
  -> Modules/BRUV

Modules/PAM  -> Core, UI
Modules/BRUV -> Core, UI, SharkTrackKit
UI           -> Core
Core         -> no PAMFlow package dependencies
```

Feature modules must not depend on each other. `Core` must stay module-agnostic and must not import UI or feature modules. `UI` can provide reusable screens and protocols, but it must not hardcode PAM, BRUV, RUV, SharkTrack, or PAMGuard behavior. The only place the app should explicitly mention which modules are included is the app composition layer in `App/ModuleComposition`.

## App Host

The app target wires the product together:

- `PAMFlowApp` creates the app-level services and module catalog.
- `AppCoordinator` starts, resumes, exits, and displays the current module workflow.
- `IncludedModules` maps build-time module selection flags to concrete feature modules.
- `Dependencies` exposes only shared services that every module is allowed to use.

The host should not know the internal screens in a workflow. It asks a module coordinator to start or resume a project, then displays the module coordinator's current screen.

## Core

`Core` owns platform-neutral project state and shared services:

- SwiftData models for mutable app and project data.
- Module identifiers and display details.
- Generic project metadata, project workflow status, and scan summary types.
- File-system services for project folders and generic project scans.
- Shared taxonomy models and lookup service for bundled species reference data.

Core types should describe concepts that are valid across modules. Media-specific details, such as audio sample rates, frame rates, SharkTrack outputs, PAMGuard database fields, and module-specific folder names, belong in modules or module-owned scan attributes.

## UI

`UI` owns reusable interface primitives and generic screens:

- Project setup.
- Project scan progress.
- Project selection.
- Generic project overview and completion surfaces.
- Shared review containers such as manual audit or detection review shells.
- Shared components, styles, strings, metrics, and navigation protocols.

UI screens should be configured through protocols and view models. They can host generic review controls, progress indicators, and reusable content slots, but module-specific media previews, labels, export fields, workflow routing, and processing actions must come from the module.

## Feature Modules

Each feature module owns its workflow rules, resources, specialized view models, and module-specific services.

### PAM

`Modules/PAM` owns passive acoustic monitoring behavior:

- PAM file and folder configuration.
- PAM-specific scan attributes and audio preview services.
- PAM manual audit behavior.
- PAMGuard setup, waiting, processing, import, and help resources.
- PAM detection review previews, waveform and spectrogram rendering, audio playback, metadata, and export.

PAM-specific statuses and screens must stay inside the PAM module. Shared UI should only see the localized status text and actions exposed by the module.

### BRUV And RUV

`Modules/BRUV` owns both BRUV and RUV project types because the workflows share most processing and review logic:

- BRUV/RUV project setup configuration.
- SharkTrack processing and resources.
- Video and image scan attributes.
- Detection review behavior, species assignment, maxN, and export.

BRUV and RUV can expose separate module details and setup configurations while sharing the same implementation internals.

## Module Interfaces

Modules conform to `FeatureModule`. A feature module provides:

- `ModuleDetails` for ID, name, icon, and selection metadata.
- A module coordinator created with `ModuleContext`.
- Project selection progress and localized status presentation.
- Optional preview preheating for recently opened projects.

Module coordinators conform to `ModuleCoordinating`. They own the workflow's internal navigation and expose only the current screen to the app host. Screens and view models should use `WorkflowActionHandling` for high-level workflow actions such as going to the previous step, going to the next step, or exiting the workflow. They should not call app routes directly or know which screen comes next.

## Project State And Backward Compatibility

Project state is stored in SwiftData and must remain backward compatible with projects created before refactors. When moving workflow logic into modules:

- Keep persisted raw values stable.
- Prefer additive migration paths.
- Preserve legacy status handling where old projects may still contain old values.
- Store module-specific detail in module-owned fields, JSON, or scan attributes rather than adding media-specific fields to shared summaries.

`ProjectWorkflowStatus` is intentionally lightweight. Modules are responsible for translating persisted status into user-facing project selection text and primary action titles.

## Resources

Resources belong with the code that owns them:

- App-wide assets and app icons live in `App/Resources`.
- PAMGuard templates and PAM help imagery live in `Modules/PAM/Resources`.
- SharkTrack and BRUV/RUV resources live in `Modules/BRUV/Resources`.
- Shared UI resources should only live in `UI` when they are genuinely module-agnostic.

When a resource is moved into a Swift package target, it must be declared in that package manifest with `.process("Resources")`.

## Taxonomy

Species taxonomy is bundled as app reference data and stays separate from mutable project data:

```text
species.json
    -> TaxonomyService
    -> speciesID stored in project decisions
```

The app stores stable species IDs on observations or detections. Display names are resolved through the taxonomy service at runtime. The taxonomy is not imported into SwiftData, and it should remain replaceable by a generated WoRMS export without changing the app-side architecture.

## Release Module Selection

The release workflow supports selecting which modules are compiled into a release build. GitHub Actions exposes module toggles for PAM and BRUV/RUV, and `scripts/create_dmg.sh` maps those choices to Swift compilation conditions:

- `PAMFLOW_CUSTOM_MODULE_SELECTION`
- `PAMFLOW_INCLUDE_PAM`
- `PAMFLOW_INCLUDE_BRUV`

At least one feature module must be selected. Packaging removes excluded module resources from the staged app bundle so release builds only ship the resources for included modules.

## Adding A New Module

To add another workflow module:

1. Create a package under `Modules/<ModuleName>`.
2. Depend only on `Core`, `UI`, and external packages required by that module.
3. Define module details, setup configuration, file configuration, strings, resources, scan attributes, workflow statuses, and workflow coordinator inside the module.
4. Implement `FeatureModule` and `ModuleCoordinating`.
5. Add the module to `App/ModuleComposition`.
6. Add release build selection flags and packaging resource cleanup if the module should be optionally shipped.
7. Keep shared UI and Core generic; move any module-specific logic discovered during integration back into the module.

The target state is that each feature module can later run as a small standalone app for manual or automated workflow testing.
