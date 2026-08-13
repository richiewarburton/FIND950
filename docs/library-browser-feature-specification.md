# FIND950 — feature specification

## 1. Purpose

FIND950 turns a collection of Akai S900/S950 `.IMG` disk backups
into a searchable sound library.

Its primary user is a musician or producer who has preserved old S950 disks but
cannot conveniently discover or use their contents in a modern DAW. The browser
must make the useful path short:

1. find a remembered sound—or discover one by auditioning samples;
2. understand which program uses it;
3. send that program to PLAY950; and
4. play it in the DAW without rebuilding the original S950 mapping.

The browser is the catalogue and discovery layer. PLAY950 is the playback
instrument. EDIT950 (EDIT950) is the detailed disk editor.

## 2. Product principles

### Preserve the archive

Indexing, browsing, searching, dependency analysis, and auditioning must open
source IMG files read-only. An original archive must not change merely because
it was added to the library.

### Use S950 terminology

The interface should describe disks, volumes, programs, and samples. It should
not require the user to understand sectors, directory records, P9 offsets, or
command-line tools.

### Separate finding from editing

The browser should make common discovery and handoff actions immediate. EDIT950
remains available through a prominent button whenever detailed image editing is
needed.

### Keep one IMG mutation engine

The browser never creates, formats, or changes an IMG. Actions that produce or
modify an IMG are handed to EDIT950, which remains the single owner of destination
selection, capacity and collision checks, backup, serialized mutation,
rollback, and native verification. The browser may discover a program's
dependencies read-only and prepare an export request, but it must not implement
a second image-writing path.

## 3. Supported environment

- macOS 14 or newer.
- S900/S950 raw `.IMG` disk backups supported by AKAI Util.
- EDIT950 for IMG creation, export, and editing handoffs.
- The browser's bundled or separately selected compatible `akaiutil` helper for
  read-only indexing and audition extraction only.
- PLAY950 VST3 for direct DAW playback handoff.

The browser is installed as `/Applications/FIND950.app` and can be
launched from Finder, Spotlight, the Dock, or the **Open FIND950** button
in PLAY950. Normal use must not require Terminal.

## 4. Library sources and indexing

### 4.1 Adding sources

The user can add one or more folders. Folder selection supports multiple
directories in one operation. Added folders are remembered across launches.

Each folder is scanned recursively for files whose extension is `.IMG`, without
case sensitivity. Adding a folder already in the library must not create a
duplicate source.

### 4.2 Removing sources

Removing a folder removes it from the browser configuration and future scans.
It must not delete the folder, any IMG, tags belonging to other items, or files
on disk.

### 4.3 Indexed information

For every readable image the index records:

- source folder and IMG path;
- disk display name;
- contained volume names and paths;
- program and sample names, type, size, and native directory index; and
- the sample names referenced by each readable P9 program.

A malformed program must not prevent the rest of its disk from appearing. A
failed IMG must be reported while other images continue to scan.

### 4.4 Refresh behaviour

The decoded catalogue is cached in the configured library-data directory and is
shown immediately on launch. A background refresh compares each canonical IMG
path, byte size, and modification time with the cache. Only new or changed
images are reopened through AKAI Util; removed images are pruned. The user can
request the same incremental refresh manually. All configured folders remain
eligible regardless of their visibility setting.

The eye beside a folder controls whether that folder is visible in ordinary
browsing, search results, and folder filters. Closing the eye must never stop
indexing, remove the folder, or alter its files. Library statistics report the
visible disk, program, and sample totals.

## 5. Browsing, searching, and filtering

### 5.1 Disk browsing

The disk list displays the familiar IMG filename and its program/sample counts.
Selecting a disk displays its volumes, programs, and samples.

### 5.2 Search scopes

The search control has two scopes:

- **Selected Disk** searches the displayed disk.
- **Entire Library** searches every visible source folder.

Matching is case-insensitive and accepts a partial program or sample name.
Results identify the disk and volume containing the item.

Scope affects only a non-empty search. Merely choosing **Entire Library** must
not replace or clear the selected disk's ordinary contents. The scope control is
a compact search option rather than a primary navigation mode.

### 5.3 Filters

Browsing and search can be narrowed independently by:

- source folder; and
- tag.

Folder and tag filters can be combined. Clearing filters restores the complete
eligible display. Filters change only presentation; they do not change the
index or source files.

## 6. Tags

IMG disks, programs and samples can have zero or more tags. The user can:

- create a tag;
- change its name;
- change its colour;
- assign or remove it from an IMG, P9 program or S9 sample; and
- delete it from the library.

Assigned tags appear beside IMG disks and native items. Deleting a tag removes its assignments
but never removes or modifies a program, sample, or IMG.

After a colour is selected, the macOS colour chooser closes rather than
remaining over the tag editor.

Tags and assignments use the shared 950TOOLS tag library selected by FIND950 and
are available in EDIT950 at the same time. Cross-process writes are locked,
merged against the latest document and replaced atomically. They are not written
into IMG, P9 or S9 files. An IMG assignment is tied to its canonical path; a
native assignment additionally uses the volume path, item kind and normalized
sampler-visible filename. EDIT950 migrates an assignment after a verified rename
and removes it after verified deletion.

Settings show the exact shared `tags-v2.json` path. The user can reveal the live
file, export a portable JSON copy, relocate it to a chosen local or synced
folder, or reset it to the default Application Support location. Relocation
keeps the previous copy as a backup. If the destination already contains a
different index, the user must explicitly use it, replace it with the current
index, or cancel. Synced locations are supported for portability, but concurrent
tag editing on multiple Macs is not. The generated FIND950 search cache has a
separate location.

## 7. Safe sample audition

Every sample has an **Audition** action.

When selected, the browser must:

1. open the source IMG read-only;
2. export only the chosen sample as a temporary WAV;
3. play the WAV through the normal macOS audio output; and
4. remove the temporary workspace when playback stops, completes, or fails.

Only one sample may audition at once. Auditioning must never normalise, rewrite,
or otherwise change the archived sample or image.

## 8. Program/sample relationships

For a selected sample, **Programs Using This Sample** shows programs in the same
disk volume whose P9 keygroups reference that sample name.

Name comparison is case-insensitive and ignores the native S9 filename
extension. Duplicate references within one program produce only one program
result.

If no relationship is found, the interface must distinguish “no referencing
program found” from a scan failure. The results panel provides the same tag,
PLAY950, and export actions as an ordinary program row.

## 9. PLAY950 integration

### 9.1 Launching the browser

PLAY950 provides a visible **Open FIND950** button. It locates the app by
bundle identifier `com.e45recordings.FIND950`, with
`/Applications/FIND950.app` as the normal installed location.

If the app is unavailable, PLAY950 displays a useful installation message
instead of silently failing.

### 9.2 Opening a program

Every program row provides a prominent **Open in PLAY950** action. The browser
sends the source IMG path and program name to an open PLAY950 editor using the
distributed notification `com.e45recordings.PLAY950.LoadContent`.

PLAY950 loads the complete IMG through its existing read-only workflow, then
selects the requested program by case-insensitive display name. The browser must
tell the user that a PLAY950 editor needs to be open in the DAW.

The handoff does not copy or edit the source IMG. Project-state persistence
after loading remains PLAY950's responsibility.

## 10. EDIT950 integration

**Open in EDIT950** is visible at the top of a selected disk and is
also available from relevant program actions.

The browser recognizes the preferred EDIT950 product identifier
`com.e45recordings.EDIT950` and the installed legacy bundle identifier
`com.local.AKAIImageManager`, with the standard Applications locations as
fallbacks. It opens the selected IMG or structured request in EDIT950 through macOS
rather than modifying the image itself.

If EDIT950 cannot be found, the user can select the application manually. See
[EDIT950 interoperability](edit950.md) for tool and format
references.

### 10.1 Export handoff

Program rows provide an **Export Program to IMG…** action. The browser resolves
the selected P9 and its referenced S9 dependencies without changing the source
IMG, then sends EDIT950 a structured request containing:

- the canonical source IMG path and volume path;
- the selected program's native identity and display name; and
- the dependency names discovered by the browser, for presentation and
  cross-checking rather than as authority to bypass EDIT950 validation.

EDIT950 then presents the export destination and image-format choices and owns the
entire mutation. If EDIT950 is unavailable, the browser explains that EDIT950 is
required for IMG export and offers to locate it. It must not fall back to
writing an IMG itself or invoke mutating `akaiutil` commands.

### 10.2 Exact native-file collection handoff

The Collection accepts any explicit combination of indexed P9 programs and S9
samples, including an S9-only or P9-only selection. **Export to Fresh IMG…**
sends those exact native identities to EDIT950. Unlike **Export Program to
IMG…**, collection export does not expand a P9 into its dependency closure and
does not reject a P9 because a referenced S9 is absent. The collection view
states that linked samples must be collected explicitly when wanted.

FIND950 still blocks capacity overflow and sampler-visible filename collisions.
EDIT950 reopens every source read-only, verifies each requested directory entry
and source fingerprint, copies samples before programs, and byte-verifies the
exact listed files in the newly created IMG.

The handoff mechanism must be versioned and must reject an unsupported request
version with a bounded user-facing error. Paths and item identities are passed
as structured values rather than shell command text.

## 11. Program export through EDIT950

### 11.1 Export to a new IMG

After accepting the browser's request, EDIT950 lets the user choose:

- destination filename and folder;
- S950 low density (800 KB) or high density (1.6 MB); and
- whether to open the result in PLAY950.

EDIT950 re-resolves the selected native P9 and exactly the referenced S9 samples
from the source, creates and formats the destination image, imports the files,
and verifies the resulting directory. Browser-supplied dependency information
may be compared with EDIT950's result to detect a stale index, but EDIT950's current
read of the source is authoritative.

An existing destination must not be overwritten by the “new IMG” workflow.

### 11.2 Export to an existing IMG

Before changing an existing destination, EDIT950 always creates and byte-verifies a
complete timestamped backup. Focused export does this regardless of the optional
backup preference used by other operations. The source IMG cannot also be the
destination, including through a symlink.

If any destination filename collides, the operation stops rather than replacing
content. If import or verification fails, the destination is restored from the
backup.

### 11.3 Dependency and verification failures

The browser reports missing or ambiguous dependencies found during read-only
analysis before offering the handoff. EDIT950 independently repeats the dependency
and source checks immediately before mutation and fails clearly if a referenced
sample is missing or ambiguous.

A successful result requires EDIT950 to verify that the selected P9 and every
required S9 appear in the destination listing after import. The browser may
display completion information returned by EDIT950, but it does not determine or
claim mutation success independently.

## 12. Persistence and privacy

The browser stores locally:

- configured folder paths;
- eye-enabled search settings;
- the shared tag-library location, tags, colours, and IMG/P9/S9 assignments;
- a decoded per-IMG catalogue keyed by path, size, and modification time; and
- normal macOS application preferences.

No library contents are uploaded. The browser does not maintain its own copies
of archived images or samples, except short-lived audition and read-only
dependency-analysis workspaces in the system temporary directory. EDIT950 owns any
staging workspace used for IMG export.

## 13. Error handling

Errors must be expressed in user terms and identify the affected disk, program,
or sample where possible. A failure in one IMG must not discard successfully
indexed disks.

Index refresh runs in the background without covering or clearing cached
library content. Export-request preparation may prevent conflicting browser
actions. Once EDIT950 accepts a request, EDIT950 owns export progress, cancellation,
errors, and completion reporting. Cancellation of a file or folder chooser is
not an error.

## 14. Acceptance criteria

The feature is acceptable when all of the following are true:

- The app launches normally without Terminal and from PLAY950.
- Two or more independently selected folders remain configured after relaunch.
- Closing a folder's eye removes its disks from browsing, search, and filters
  but does not remove them from the index.
- Library statistics show visible disk, program, and sample totals.
- An IMG, P9 program or S9 sample can be tagged or untagged; assignments are
  visibly presented and found again after relaunch or in EDIT950.
- The colour chooser closes after a tag colour is selected.
- A warm launch displays cached disks immediately and invokes AKAI Util only for
  new or metadata-changed IMG files.
- Selected-disk and whole-library searches return correct partial-name matches
  and respect folder/tag filters.
- Changing search scope without entering a query leaves the selected disk
  visible.
- Audition plays a temporary WAV and leaves the source IMG byte-for-byte
  unchanged.
- A known P9/sample fixture returns the expected programs using that sample.
- Open in EDIT950 visibly launches EDIT950 with the chosen disk.
- Open in PLAY950 loads the chosen disk and selects the requested program.
- Export Program to IMG hands a versioned, structured source/program request to
  EDIT950 and never invokes an IMG-writing command in the browser process.
- EDIT950 re-resolves dependencies from the source; a deliberately stale browser
  index cannot cause incomplete or incorrect content to be written.
- New-image export performed by EDIT950 contains the chosen P9 and all referenced
  S9 files at the selected density.
- Existing-image export performed by EDIT950 creates a backup, rejects collisions,
  and restores the original on a simulated failure.
- If EDIT950 is missing or rejects the handoff version, the browser reports the
  problem without creating or changing an IMG.
- Malformed and missing files produce bounded errors without crashing or
  corrupting the library.

## 15. Current boundary

The browser is not a replacement for EDIT950, a DAW, or an S950 program editor. It
does not create, format, or mutate IMG files, and it does not edit keygroups,
sample data, loop points, tuning, or program parameters. EDIT950 is the sole IMG
mutation engine; PLAY950 owns DAW playback and project-state persistence.
