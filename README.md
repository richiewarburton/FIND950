# FIND950

<p align="center">
  <img src="docs/images/find950.png" width="180" alt="FIND950">
</p>

<p align="center"><strong>BROWSE · SEARCH · COLLECT</strong></p>

[![macOS Swift CI](https://github.com/richiewarburton/FIND950/actions/workflows/ci.yml/badge.svg)](https://github.com/richiewarburton/FIND950/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/license-MIT-3455ff.svg)](LICENSE)

## Make a folder of old sampler disks feel like a searchable library

You did the difficult part: the S900/S950 floppies were rescued as `.img` files
before the disks or drives failed. Maybe you used a Greaseweazle, copied a Gotek
collection, or inherited somebody else's archive. Now there are hundreds of
files with names such as `DISK001.img`, and opening them one at a time is almost
as inconvenient as using the floppies.

FIND950 indexes that folder and lets you:

- search the original program and sample names across every IMG;
- audition samples without extracting and organising WAV files first;
- tag whole IMG disks, individual P9 programs and S9 samples using the same
  colour-coded tags as EDIT950;
- find every P9 program on a disk that refers to a particular S9 sample;
- collect any exact set of P9 and S9 files into a new verified IMG;
- open the exact disk in EDIT950 for editing; and
- send the exact program towards PLAY950 for use in a DAW.

The source images are opened **read-only**. Scanning, searching, tagging and
auditioning cannot alter your archive. You do not need the original sampler.

Current public release:
**[0.2.3 (build 5)](https://github.com/richiewarburton/FIND950/releases/tag/v0.2.3)**.
The Universal macOS app supports Apple Silicon and Intel and requires macOS 14
or later.

![FIND950 searching a multi-folder IMG library](docs/images/find950-library.png)

*Select a disk to see its native P9 and S9 contents, audition samples, follow
program dependencies, or hand the exact sound to EDIT950 or PLAY950.*

## Is this for my collection?

Yes, if your S900/S950 backup workflow produced ordinary `.img` disk images.
Greaseweazle raw flux captures, `.scp` and `.hfe` files are valuable archival
masters but are not indexed directly; export or convert a compatible IMG copy
and keep the original capture safe.

The browser works with files on your Mac or attached storage. It does not read,
format or write physical floppy drives.

## How to use FIND950

1. Add the folder containing your IMG collection. Subfolders are supported.
2. The first pass reads the disk directories and native P9/S9 metadata.
3. Select a disk in the sidebar to browse it. Use the eye beside a source folder
   to show or hide its disks throughout browsing, search, and filters. The
   library stats show totals for the visible folders.
4. Use the search button for names, or the filter menu for folders and tags.
   Clear the search to return to ordinary browsing.
5. Use the tag menu in the disk header or beside a P9/S9 to assign a colour-coded
   tag. Assigned tags remain visible as chips and changes appear in EDIT950 too.
6. In **Settings → Shared Tag Index**, reveal or export the live JSON index, or
   relocate it to a local or synced folder chosen by you. Avoid editing tags on
   multiple Macs simultaneously when the index is synced.
7. Press **Audition** beside an S9 sample to hear it.
8. Choose **Programs Using This Sample** to recover the original P9 programs
   that made the sample musically useful.
9. Use **Open in EDIT950** to edit the disk, **Program Actions →
   Export Program to IMG…** to create a focused working disk in EDIT950, or **Open
   in PLAY950** to load the mapping in an open plug-in editor.
10. To copy individual native files, add any P9 and/or S9 rows to the
    **Collection**, then choose **Export to Fresh IMG…**. Collection export copies
    exactly those files; it does not add a P9's linked samples automatically.

The decoded catalogue is cached. On later launches, results appear immediately
while a background pass checks paths, sizes and modification times. Only new or
changed images are reopened by AKAI Util.

## What is preserved

This is more than a filename search. Programs are indexed with their native
sample references, so the relationship between a P9 and its S9 files remains
visible. The workflow is designed to retain the information that made an S950
program work: sample assignments, key ranges, tuning, loops, velocity layers
and other native program structure.

Audition creates one private temporary WAV, plays it, and removes it when
playback stops. It does not create a second loose WAV library or modify the IMG.

## Installation

Download the latest Universal macOS ZIP from
[GitHub Releases](https://github.com/richiewarburton/FIND950/releases/latest),
open it, and move `FIND950.app` to `/Applications`. The community build is
ad-hoc signed rather than Apple-notarized, so macOS may require you to
Control-click the app and choose **Open** the first time.

To install the current source build on a Mac with Xcode instead:

```sh
git clone https://github.com/richiewarburton/FIND950.git
cd FIND950
./Scripts/install-browser-app.sh
```

That installs **FIND950.app** in `/Applications`, so it can be
opened from Finder, Spotlight, the Dock or PLAY950 without a Terminal window.

The browser uses AKAI Util for read-only decoding. The easiest setup is to
install [EDIT950](https://github.com/richiewarburton/EDIT950)
first; FIND950 finds EDIT950's bundled Universal helper automatically. An
alternative AKAI Util executable can be selected in settings.

Developers can instead run:

```sh
swift run "FIND950"
```

There is also a command-line catalogue view:

```sh
swift run find950-cli "/path/to/your/IMG folder" --recursive
```

## From finding a sound to using it

FIND950 is the discovery part of the
[950TOOLS](https://github.com/richiewarburton/950TOOLS) workflow:

| Product | Job |
| --- | --- |
| **FIND950** | Find, index, tag and audition the archive read-only. |
| [EDIT950](https://github.com/richiewarburton/EDIT950) | Inspect, edit and safely create or modify IMG files. |
| [PLAY950](https://github.com/richiewarburton/PLAY950) | Play native programs in a DAW and recall them with the project. |

> **Find in FIND950, modify in EDIT950, play and recall in PLAY950.**

The public Universal PLAY950 VST3 is available from its
[GitHub Releases page](https://github.com/richiewarburton/PLAY950/releases/latest).

When you choose **Export Program to IMG…**, FIND950 sends EDIT950 the exact
source IMG, volume, P9 identity, source fingerprint and a read-only preview of
its sample dependencies. EDIT950 re-reads the current native program, chooses the
destination with you, performs the export and verifies the result. FIND950
never creates, formats, backs up or writes the destination itself.

Collection export is deliberately different: it copies exactly the P9 and S9
files collected in FIND950. This permits an S9-only or P9-only IMG, including a
P9 whose referenced samples are unavailable. Collect the linked S9 files too
when the destination should contain a complete playable program.

When a PLAY950 editor is open in your DAW, **Open in PLAY950** asks it to load
the selected IMG and program. The targeted, acknowledged PLAY950 handoff is a
later protocol phase; the current bridge requires an open editor.

## Safety boundary

FIND950's AKAI Util session is structurally read-only:

- it always launches AKAI Util in read-only mode;
- mutating commands such as format, put, delete and rename are centrally
  rejected;
- source fingerprints are calculated before an EDIT950 handoff;
- temporary audition files live outside the archive; and
- destination selection and every IMG mutation belong to EDIT950.

Keep an independent archival backup anyway—especially when the IMG files are
your only surviving copy of the original disks.

## Current scope

Working now:

- multiple remembered library folders and recursive indexing;
- selected-disk and whole-library search;
- shared colour-coded IMG/P9/S9 tags, visible assignment chips, and folder/tag
  filtering, with a user-selected shared index location and JSON export;
- program-to-sample dependency lookup;
- temporary read-only sample audition;
- cached launch with changed-image background refresh;
- direct Open in EDIT950 and PLAY950 actions; and
- verified protocol-v1 focused and exact-collection export handoffs to EDIT950.

The complete behaviour and acceptance criteria are in the
[FIND950 feature specification](docs/library-browser-feature-specification.md).
Interoperability details are in
[EDIT950 interoperability](docs/edit950.md).

## Build and test

```sh
swift build
swift test
./Scripts/install-browser-app.sh
```

## Independence and licence

This community project is not affiliated with, endorsed by or sponsored by
Akai Professional. “Akai” and “S950” are trademarks of their respective owners.

The repository is licensed under the [MIT License](LICENSE). Third-party tools,
sample libraries, disk images, trademarks and documentation retain their own
licences and terms.
