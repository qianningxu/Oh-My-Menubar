# Native resize previews — 2026-09-10

## Behavior

Based on upstream WinMux `e0ad328e109cb6d2f86b1bdbc3aea9bf7bc5935e`, specifically `mouse/resize/resizeWithMouse.swift` and `mouse/driver/WindowMouseInteractionOpacity.swift`: park neighboring native windows off screen while presenting their proposed layout, then restore native windows after release. Opacity alone does not reliably hide foreign-window edges.

The user requested shading on **both** sides with app icons and without preview bars. Both previews are committed in the same compositor transaction. The opaque backing uses the existing workspace canvas color, covers the divider and outer margins, and stops below the workspace tabs. Final native writes finish beneath the preview before reveal; parked windows are not restored to obsolete pre-drag frames.

The existing minimum-layout calculation still includes inactive tabs. The initial pointer offset is preserved. Resize sessions have unique identities; stale calibration callbacks are rejected, queued AX writes are canceled on stop, and the event constraint expires and clears on mouse-up or a disabled event tap.

The drag loop also follows upstream's current-pointer rendering in both calibration branches and initial setup, its 30 Hz calibration interval, and its early return for continuing resize/move notifications. An extracted-production-method regression check confirms a delayed native width of 450 cannot replace a current pointer-derived width of 500, including the first calibration. Detailed frame tracing is disabled outside explicit verification.

## Verification

Installed signed app, Built-in Retina Display, 1728 × 1117 logical points:

- Fast 120-point Figma resize, including reversal before release.
- Fast 100-point ChatGPT resize from the opposite side.
- Slow and fast 500-point attempts beyond the Figma minimum, hold, and reversal.
- Slow Safari resize with Figma inactive.
- Fast limit attempt with Safari active and Figma inactive.
- Fast 80-point resize of unfocused Safari; native width reached 980 then returned to 900.
- Every completed initial scripted round trip returned to the same native 900/810 widths and 6-point gap.
- 737 final two-pane preview trace samples: gap minimum/maximum **6/6**, Figma/Safari stack minimum **900**.
- Inspected screenshots during drag and after release: both shaded panes; no preview bars; workspace-colored gaps; no native corner slivers; native windows and normal chrome restored.

During a drag, native-neighbor coordinates intentionally describe parked windows. Gap measurements above use the shared preview geometry, not those hidden native frames.

Pure-source checks passed for event-gate expiry, negative-origin bounds, immutable pointer offsets, reversal after correction, and native minimum learning. Focused XCTest cases were added for expired constraints and distinct same-window resize sessions. Full XCTest execution is unavailable in this machine's CommandLineTools environment (`no such module XCTest`).

Only one physical monitor was available, so cross-monitor live testing remains unverified. The final automated suite did not separately exercise tab reordering or native move gestures; their existing presentation paths retain the default detailed preview.

## Initial shared-shade handoff

`make install` built and signed the combined source snapshot, passed the Accessibility code-requirement preflight, and replaced PID 97298 with PID 99972 at `/Applications/WinMux.app/Contents/MacOS/WinMux`. Independently verified the old PID exited, the installed signature, and identical installed/candidate SHA-256:

`e29852e8ed2ba56cfa817d05868da6e6d908b13c8f95b12f9b39dd563dcdb5a2`

Local evidence: `/tmp/winmux-final-*.json`, `/tmp/winmux-final-shade-drag.png`, `/tmp/winmux-final-shade-release.png`, `/tmp/winmux-resize-trace.log`, and `/tmp/winmux-gap-match-install.log`.

## Final icons and pointer-update verification

With detailed tracing disabled, the final installed build passed the calibration regression check and completed fast/limit round trips at the user's updated starting widths (1172/538 and 1178/532), preserving each starting layout and the 6-point released gap. An initial fast attempt was aborted on pointer interference and rerun after detecting an idle pointer. Inspected `/tmp/winmux-upstream-icons-drag.png`: app icons on both shades, no bars, workspace-colored divider and outer gutters, and no corner slivers.

Final signed installation: old PID 7121 exited; PID 9795 ran from `/Applications/WinMux.app/Contents/MacOS/WinMux`. Installed and candidate signatures/hashes verified. SHA-256: `4cb8dee9c0a3cca50ea96508b32a4c51c5c22db391b1c449eb5011a4645e44f4`. Installation log: `/tmp/winmux-upstream-latency-install.log`. This verifies behavior and the removal of stale-frame redraws; it is not a measured end-to-end latency benchmark.
