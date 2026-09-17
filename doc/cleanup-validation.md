# WinMux cleanup validation — 7 September 2026

## Changes

Removed the unused vertical rendering entry point, expansion controls, hover timers, and obsolete sidebar screenshots. Shared interaction helpers and active compatibility adapters remain. UI copy, CLI help, configuration comments, and README now use tab bar, widget bar, window stack, and stack tabs terminology, with sentence-case actions.

Tab snapshots reuse a bound-window inventory within one refresh. Bar-width normalization no longer schedules a window-layout refresh. Existing persistent caches, adaptive polling, configuration keys, command aliases, and saved data formats remain compatible. All declared package dependencies are still used.

## Checks

- Debug app build passed.
- `swift test` was attempted before and after the cleanup. Both attempts failed at compilation because the installed command-line developer tools do not provide XCTest. No full-suite pass is claimed.
- A standalone executable linked the debug app modules and existing test fixtures, with assertion checks in place of XCTest. It passed snapshot equality against the pre-cleanup builder for 20 tabs/200 windows, fresh counts after closing a window, custom labels, and zero scheduled layout refreshes during bar normalization.
- Eight existing horizontal-bar and menu-bar scenarios passed in that harness: notched/fallback geometry, negative display origin, tab reorder/folder destination, project projection, popup sizing, and window levels.
- The existing AX refresh and post-command benchmark scenarios passed in the harness: focus/activation avoided full refreshes, window creation retained 10 refreshes and normalizations, and safe/unsafe commands scheduled 0/10 refreshes respectively.
- Three XCTest regression cases were added for snapshot freshness, labels, and bar normalization, ready to run with full Xcode.

## Performance evidence

Alternating six trials of 100 snapshot builds with 20 tabs and 200 fixture windows gave median totals of 687.29 ms before and 676.31 ms after (1.6% lower). Other local workloads introduce timing noise; this is a modest debug-fixture improvement, not a claimed end-to-end UI speedup. Redundant full-window layout scheduling was eliminated from bar normalization.

Only one physical display is connected. Synthetic multi-display geometry checks passed; physical multi-display interaction and live window dragging were not verified.

## Installed-app checks and cleanup

The signed release passed the existing Accessibility-grant compatibility check and strict signature verification. Installation retired PID 51078 and launched PID 56720 from `/Applications/WinMux.app/Contents/MacOS/WinMux`. Tab cycling and restoration, project-menu labels, and opening/dismissing the sleep chart were exercised live. The command-line client and installed server report matching build versions.

Six successful wrapped tab-switch commands had a median round trip of 56.6 ms before and 36.1 ms after installation. These measurements include process launch and IPC and ran amid other local work; they are smoke measurements, not evidence of a 36% application speedup. Idle CPU samples were also noisy, with no defensible idle-performance claim.

The bundled configuration parsed identically to the pre-cleanup version, and all 37 CLI help/description string assertions passed in a direct text check.

Removed 17 obsolete paths totaling 6.96 GiB in allocated file size: the old June download, app/binary backups, an unchanged ancestor checkout, the repository's tracked backup executable, and temporary build/module caches. Source-only staging snapshots and application data were retained. The current release archive remains available. Filesystem free-space gains may differ because of APFS sharing.

A concurrent bar-layer update was preserved. Its current production enum was compiled separately and passed assertions that the bar stays at the dock-window level, below notification banners and the system menu bar.

Final combined install verification: PID 56720 exited; PID 59752 runs the installed executable. Its hash matches the signed candidate, and source hashes remained unchanged during the final build. The superseded debug build was also removed, bringing cleanup to 18 paths and 7.72 GiB of allocated artifacts.
