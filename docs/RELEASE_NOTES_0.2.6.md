# FIND950 0.2.6 (build 8)

FIND950 0.2.6 adds user-visible diagnostics and cross-app removable-media
coordination. It contains the fixes and enhancements developed after the 0.2.5
GitHub release; the 0.2.5 PolyForm Internal Use licensing terms remain
unchanged.

## User-visible diagnostic timeline

- Added a persistent, rolling activity log with bounded disk usage.
- The log covers application lifecycle, folder changes, scans, IMG/native-file
  selection, search scope, tag and related-program dialogues, sample audition,
  WAV export, EDIT950/PLAY950 handoffs, collection export, Safe Eject, notices
  and errors.
- IMG, P9, S9 and audio contents are never written to the diagnostic log.
- Home and temporary paths are shortened before they enter the readable log.
- Added an in-window log viewer with **Copy**, **Save**, **Reveal** and **Clear**
  controls.
- Added an option to expose the log automatically when an error occurs.
- The saved report is ordinary readable text suitable for attaching to a bug
  report while preserving the rolling live log.

## Safe Eject coordination with EDIT950

- Added the same shared cross-process removable-volume lease protocol used by
  EDIT950 1.8.25.
- FIND950 holds a volume lease only while it is actually reading: scanning,
  extracting temporary audition audio, exporting a WAV, or preparing/waiting
  for an EDIT950 handoff.
- Selecting or browsing an already cached IMG does not falsely keep its removable
  volume busy.
- Safe Eject checks for active EDIT950 and FIND950 leases before cleanup
  inspection or deletion.
- If EDIT950 has any IMG on the same volume open, or FIND950 is actively reading
  that volume, eject stops with a specific operation message. The drive remains
  mounted and no metadata is removed.
- An acquired eject lease prevents a new scan/export/handoff from starting on
  the volume until native macOS eject succeeds or the operation is cancelled.
- Stale leases from a terminated process are detected and removed.
- After a successful eject, FIND950 retains its cached catalogue, marks the media
  offline and reconnects it when the same volume returns.

## Validation

- 25 FIND950 tests passed with 0 failures.
- New coordination coverage proves that companion use blocks eject before a
  `.DS_Store` test candidate can be touched, that new work is refused during an
  acquired eject and that an app may safely close its own volume session.
- Diagnostic coverage verifies persistence, path shortening, bounded retention,
  copy/export content and user clearing.
- Existing read-only AKAI Util session, incremental/offline scan, native metadata,
  audition export, tag migration, collection/focused handoff and cleanup safety
  tests continue to pass.
- The packaged FIND950 application and bundled AKAI Util helper are Universal
  `arm64`/`x86_64`, ad-hoc signed and archive-verified.

## Licensing and distribution

Current original FIND950 material remains source-available under PolyForm
Internal Use 1.0.0 with the additional permissions described in `LICENSING.md`.
AKAI Util remains GPL-2.0-or-later and JetBrains Mono remains OFL-1.1. This
community build is ad-hoc signed and is not Apple notarized.
