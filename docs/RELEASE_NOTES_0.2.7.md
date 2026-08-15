# FIND950 0.2.7 (build 9)

FIND950 0.2.7 contains the diagnostics, removable-media coordination and
appearance changes developed after the 0.2.5 GitHub release.

## Appearance

- Added System, Light and Dark themes in Settings and the View menu.
- Shared the selected appearance with other supporting 950TOOLS applications.
- Kept Display zoom, table density and pane visibility as separate FIND950
  preferences.

## User-visible diagnostic timeline

- Added a persistent rolling activity log with bounded disk use.
- The log covers application lifecycle, folder changes, scans, IMG/native-file
  selection, search scope, tags, related programs, sample audition, WAV export,
  EDIT950/PLAY950 handoffs, collection export, Safe Eject, notices and errors.
- IMG, P9, S9 and audio contents are not written to the diagnostic log.
- Home and temporary paths are shortened in the readable log.
- Added an in-window viewer with **Copy**, **Save**, **Reveal** and **Clear**.
- Added Settings controls to show, save or reveal the log and to open it
  automatically when an error occurs.

## Safe Eject coordination with EDIT950

- Added the same cross-process removable-volume lease protocol used by
  EDIT950 1.8.37.
- FIND950 holds a volume lease only while scanning, extracting temporary
  audition audio, exporting a WAV or preparing an EDIT950 handoff.
- Browsing a cached IMG does not falsely keep its removable volume busy.
- Safe Eject checks active EDIT950 and FIND950 leases before cleanup inspection
  or deletion.
- If either application is actively using the volume, eject stops with the
  application and operation named. The drive remains mounted and no configured
  metadata is removed.
- An eject lease prevents new scan, export or handoff work on the volume until
  native macOS eject succeeds or is cancelled.
- Stale leases from terminated processes are removed.
- After a successful eject, FIND950 retains its cached catalogue, marks the
  media offline and reconnects it when the same media returns.

## Validation

- 25 FIND950 tests passed with 0 failures.
- Coordination coverage verifies that companion use blocks eject before a test
  cleanup candidate can be touched, that new work is refused during an eject
  lease and that an application can close its own volume session.
- Diagnostic coverage verifies persistence, path shortening, bounded retention,
  copy/export content and user clearing.
- Existing read-only AKAI Util, incremental/offline scan, native metadata,
  audition export, tag migration, collection/focused handoff and cleanup safety
  tests continue to pass.
- The packaged FIND950 application and bundled AKAI Util helper are Universal
  `arm64`/`x86_64`, ad-hoc signed and archive-verified.

## Licensing and distribution

Current original FIND950 material remains source-available under PolyForm
Internal Use 1.0.0 with the additional permissions described in `LICENSING.md`.
AKAI Util remains GPL-2.0-or-later and JetBrains Mono remains OFL-1.1. This
community build is ad-hoc signed and is not Apple notarized.
