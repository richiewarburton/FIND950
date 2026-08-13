# AKAI Util 4.6.7 provenance

- Upstream: `akaiutil-4.6.7.tar.gz`
- Published by Klaus Michael Indlekofer on 21 October 2022.
- Download: `https://sourceforge.net/projects/akaiutil/files/akaiutil-4.6.7.tar.gz`
- Upstream archive SHA-256:
  `b9b72f7af0a40ec8021bfe23c16bd2c1f17dc80308be5e1249d4d7dac94fdb49`
- Licence: GPL version 2 or later; see `gpl-2.0.txt`, `README.txt` and the
  copyright headers in the source.

FIND950 carries one macOS compatibility change in `commoninclude.h`: Apple SDKs
define fortified function-like macros named `bcopy` and `bzero`, so those macros
are undefined before AKAI Util's existing declarations. No filesystem, parsing,
conversion, command or disk-writing behaviour is changed.

FIND950 launches this helper only in AKAI Util's read-only mode and also rejects
commands outside its explicit read-only allow-list.
