# EDIT950 interoperability

## Why it is separate from the VSTi

Disk-image management and real-time audio have different constraints. Image
tools need broad format support, careful recovery behaviour, and explicit write
operations. A plug-in must load quickly, process audio deterministically, and
avoid mutating a user's source media. Keeping the boundary explicit gives both
parts a smaller, testable responsibility.

The VSTi should therefore consume a portable interchange package produced by an
image manager. It should not modify an original S900/S950 disk image in place.

## Implemented Phase 1 interchange contract

Focused export uses the 950TOOLS protocol-v1 `.akaitoolsrequest` document.
FIND950 fingerprints the complete source IMG, supplies the exact volume,
P9 directory index and filename plus its observed dependency identities, and
opens that data document with EDIT950. EDIT950 acknowledges through an atomic sibling
response document and returns typed verification evidence only after it owns and
verifies the export. The request never contains a command.

## Proposed portable-package contract

An imported library should contain:

- decoded audio as WAV, without normalisation or other destructive processing;
- original sample rate, tuning, loop points, and root-note metadata;
- program and keygroup mappings, including velocity ranges where available;
- a manifest with source format, conversion-tool version, and checksums; and
- optional preservation of the untouched source image outside the plug-in's
  writable library.

Portable program packages remain future work. EDIT950 always reopens an IMG source
for Phase 1 and treats the browser's dependency list only as stale-index
evidence.

## Important external links

### akaiutil

- [Project and downloads](https://sourceforge.net/projects/akaiutil/)

`akaiutil` is the most relevant open-source reference currently identified. Its
project description explicitly covers S900 and S950 disk images and storage,
read/write/format operations, WAV conversion, and the S900 compressed sample
variant. It is useful both as an interoperability tool and as a behavioural
reference, subject to its GPLv2 licence and bundled disclaimers.

### HxC Floppy Emulator

- [Software and supported formats](https://www.hxc2001.com/floppy_drive_emulator/)

HxC documents support for Akai S900/S950 raw-sector images and is relevant when
moving libraries between a computer and HxC/Gotek-style floppy emulators. HxC
images are transport media; they should not become the VSTi's native preset
format.

### S900/S950 floppy-format notes

- [Chicken Systems: Akai S900/S950 floppy image information](https://www.chickensys.com/translator/documentation/floppyimageinfo/akais9x.html)

This is a useful high-level description of S900/S950 floppy capacity, sample
representation, and program constraints. It is secondary documentation rather
than a normative file-format specification, so behaviour should be confirmed
against real images and independent implementations.

### Original S950 documentation

- [Akai S950 owner's manual scan](https://manuals.fdiskc.com/flat/Akai%20S-950%20Owners%20Manual.pdf)

The owner's manual is the best reference in this list for the sampler's visible
workflow and terminology. A third party hosts this scan; do not redistribute it
in this repository without permission.

## Safety and legal notes

- Work on copies and keep original images read-only.
- Do not publish commercial sample libraries, firmware, ROMs, or manuals unless
  their licence clearly permits redistribution.
- Treat malformed images as untrusted input and validate sizes, offsets, counts,
  and names before decoding.
- Preserve provenance: converted files should retain the source-image checksum
  and conversion-tool version.
- Compatibility does not imply affiliation with Akai Professional.
