# Project and workspace appearance

The native implementation uses Geist token roles and the custom WinNotch glass compositor.

| Name | Meaning | Appearance |
| --- | --- | --- |
| Widget bar | Status widgets supplied by the independent My Menu Bar app | Clear custom glass with backdrop blur and a 20% white tint, without an added outline; safe around the camera notch |
| Project frame | Former full-screen surface beneath the Widget bar | Removed; the desktop remains visible through window gaps |
| Workspace tabs bar | Workspace-only bar beside the camera notch | Content-sized custom glass surface with maximum-strength color-neutral backdrop blur and a 60% white tint composited at 80% surface opacity, plus a fully opaque white border and rounded shadow; active or hovered labels are fully opaque and medium weight, while inactive labels are 50% opaque and regular weight |
| Workspace frame | Window layout area | No enclosing fill; each window and window tab bar owns its surface |
| Window tab bar | Compact WinDock glass track with a color-neutral backdrop, 25% blur opacity, a visible 25% white tint, and an independently rendered 45% theme-aware border. Focused and hovered labels are fully opaque, unfocused labels are 50% opaque, and icons remain fully opaque; focused labels use semibold weight, unfocused labels use regular weight, the focused segment uses an 80% white fill, and hover uses a 50% white fill. |
| Stacked window | Windows sharing one workspace tab bar | Existing grouping behavior |
| Workspace window | Native app window and title bar | Native controls, borders, and corner geometry retained |

Workspace tabs size to their text with a 200pt cap, centered labels, and subtle dividers. Project controls live in the WinNotch status-item menu rather than inside the workspace bar. Window tab bars retain their original compact 32pt tab surface inside a 34pt glass track. Window gaps expose the desktop instead of a project-frame fill.

The status-item menu's Config submenu has a global **Auto hide** setting. When enabled, the workspace bar reveals from the top edge and remains visible while its controls are in use. Switching workspaces or moving a window to another workspace briefly reveals the destination display's bar, including the default Option+number and Option+Shift+number shortcuts.

During drag previews, managed windows are hidden and the preview interior is clear, so it reveals the wallpaper rather than another window. A white outline marks the destination frame.

The names describe UI surfaces. Internal workspace/project identifiers, configuration keys, CLI commands, and stored user state keep their existing meanings for compatibility. Native window corners remain owned by their applications; the HTML mockup's simulated 20-point corners do not forcibly reshape third-party windows.

## Native frame corrections

WinDock-controlled tabs use continuous radii. The Window tab bar uses a 21-point outer radius around its inset. All bars use the shared WinDock glass compositor rather than SwiftUI's native `glassEffect`: an AppKit backdrop blur plus explicit WinDock-owned blur opacity, white tint, stroke, shadow, and focus opacity. Clear uses full blur with a 20% white tint and no shadow; regular uses full blur with a 28% white tint and a restrained shadow. Reduce Transparency falls back to the solid background surface. Navigation follows the selected light, dark, or system theme.

Each stacked window has a translucent rounded workspace tab surface aligned with the native window below. Adjacent groups share one six-point gap. Native window borders remain visible.

Workspace tabs use 16-point text, window tabs use 14-point text, and widget text remains 12 points.
