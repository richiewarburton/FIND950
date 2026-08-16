# FIND950 0.2.8 (build 10)

FIND950 0.2.8 adds a lightweight, musician-controlled update check.

- FIND950 checks the public GitHub latest-release endpoint once per launch.
- The app remains silent when current or when the network is unavailable.
- A newer release appears as a dismissible, non-modal notice with a direct link
  to its GitHub release page.
- **FIND950 → Check for Updates…** reports the installed and latest versions on
  demand.
- FIND950 does not download, replace or install application files.

Verification included all 25 package tests, a Universal `arm64`/`x86_64`
release package, strict code-signature verification, installed-version checks
and a live GitHub current-version result in the installed application. The
manual and README include that actual result as a screenshot of the new flow.
