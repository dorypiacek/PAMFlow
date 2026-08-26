# Changelog

All notable changes to PAMFlow are documented here.

## 1.0.1 - 2026-08-26

- Improved PAM audio spectrogram rendering quality with a wider 60 dB display range and Retina-aware raster sampling.
- Restored full Nyquist-frequency spectrogram display for high-sample-rate WAV files.
- Fixed waveform and spectrogram plot alignment in manual audit.
- Simplified PAMGuard event grouping to use a 2 second detection gap and 2 second review padding.
- Preserved distinct PAMGuard events even when padded review windows overlap.
- Improved PAMGuard setup resume behavior and detection overview navigation.
- Added tinted outlines to secondary action buttons.

## 1.0.0 - 2026-08-23

- Added GitHub Actions CI for pull requests and pushes to `main`.
- Added GitHub release packaging for unnotarized macOS DMG builds.
- Bundled SharkTrack runtime inside release app packages.
- Added release version checks to prevent republishing an existing app version.
- Added unnotarized macOS install guidance.
