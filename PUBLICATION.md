# ReMeizu M2 Note: lineage-16.0 source publication

This branch publishes real existing device integration work for Android 9. Original source checkpoint: `4f68010da875b5656c087220b270709c4df704a9`. The private Android 9 source view passed the LOS16 product/build-graph check on 2026-09-28; that check included external inputs omitted here. Full ROM validation is separate.

The full logical source history is retained with original authors, dates and parent relationships. Commit IDs changed because excluded files and factory-address comments were filtered. `PUBLICATION.json` maps every original commit to its published equivalent. Private original repositories have not been modified or exposed.

## Scope and external inputs

Product/board makefiles, Android module declarations, VINTF manifests, project-authored init helpers, overlays, source HAL/shim code, extraction filename lists and validation helpers are published. Kernel/prebuilt binaries, all `configs/` and `keylayout/` payloads, and stock-derived `rootdir/init.*` / `ueventd.mt6735.rc` files are excluded throughout history; their redistribution provenance has not been established by this publication. Per-tip paths and reasons are in `PUBLICATION.json`. Actual factory Bluetooth addresses were redacted from comments; executable code was not altered by that redaction.

References to omitted external inputs intentionally remain in the build descriptions. A clone by itself is **not a complete build input**. It does not bypass missing-input checks, replace stock data with dummy payloads, or imply a flash-ready ROM. Vendor binaries and matching kernel/header inputs must be separately and lawfully provided for device builds. Stock payloads remain outside the proposed source-only hosting workload.

## Licensing and credits

Existing per-file copyright and license notices are preserved. Apache-2.0 Android/LineageOS code and GPL-2.0/BSD MediaTek/wpa_supplicant source retain their original terms; no blanket relicensing is applied. Project-authored source and donor provenance are described in existing file comments and commit messages. Files without an explicit license still require a per-file licensing decision before treating the entire repository as an approved open-source build workload; public visibility alone is not a license grant.

## Verification boundary

Publication audit: all reachable commit trees checked for binary payloads, private keys, common access-token formats and factory identifiers; excluded paths absent from all published history. Git object integrity and anonymous branch/commit access are checked separately in the publication receipt. Source availability does not certify build, boot, modem, camera, suspend or hardware stability.
