---
name: sidebar-widget-creation-skill
description: Create or update built-in WinMux sidebar widgets in the project root widget folder. Use when the user asks to add a sidebar widget, make a new widget type, move widget code into sidebar_widgets, update widget config ordering/enabled behavior, or keep widget implementation separate from sidebar runtime/plugin plumbing.
---

# Create Sidebar Widget

## Overview

Add sidebar widgets to WinMux while keeping `Sources/AppBundle/sidebar_widgets` reserved for actual widget implementations. Put tracked built-ins in `core`, local user widgets in `custom`, and shared sidebar runtime, config, parser, and plugin-loading plumbing outside this folder.

## Workflow

1. Inspect the current widget system before editing:
   - `Sources/AppBundle/sidebar_widgets/`
   - `Sources/AppBundle/sidebar_widgets/core/`
   - `Sources/AppBundle/sidebar_widgets/custom/`
   - `Sources/AppBundle/ui/WorkspaceSidebarWidgetStack.swift`
   - `Sources/AppBundle/config/Config.swift`
   - `Sources/AppBundle/config/parseWorkspaceSidebar.swift`
   - `Sources/AppBundle/command/impl/ConfigCommand.swift`

2. Create widget implementation files in the right widget folder:
   - Built-in path pattern: `Sources/AppBundle/sidebar_widgets/core/WorkspaceSidebar<Name>Widget.swift`
   - Local/custom path pattern: `Sources/AppBundle/sidebar_widgets/custom/WorkspaceSidebar<Name>Widget.swift`
   - Keep helper types private inside the same file unless they are genuinely shared by multiple widgets.
   - Do not put `WorkspaceSidebarWidgetStack`, plugin loading, registry code, parser code, or config command code in `sidebar_widgets`.
   - Keep `Sources/AppBundle/sidebar_widgets/custom/.gitignore` tracked and leave all other custom folder contents ignored.

3. Add config support for a built-in widget:
   - Add a `WorkspaceSidebarWidgetType` case in `Config.swift`, using a raw value like `built-in/weather`.
   - Parse any widget-specific fields in `parseWorkspaceSidebar.swift`.
   - Preserve existing widget ordering by using the configured `widgets` array order.
   - Preserve disabled widgets in config output; filter `enabled == false` only at render time.

4. Wire rendering:
   - Update `WorkspaceSidebarWidgetStack` to switch on the new built-in type and render the new widget.
   - Keep runtime plugin rendering in `WorkspaceSidebarPluginWidget`; use it only for `type = 'plugin'`.

5. Update configuration surfaces:
   - Add the widget to `resources/default-config.toml` only if it should be enabled by default.
   - Ensure `config --get workspace-sidebar.widgets --json` exposes the widget `id`, `type`, `enabled`, and widget-specific options.
   - If starter config depends on default config, check `starterConfigText()` still parses.

## Widget File Pattern

Use this shape for root-level built-in widget files:

```swift
import SwiftUI

struct WorkspaceSidebarExampleWidget: View {
    let id: String
    let sectionWidth: CGFloat
    let isCompact: Bool

    var body: some View {
        // Keep the widget self-contained and stable at compact/expanded widths.
    }
}
```

Prefer stable dimensions with `.frame(width: sectionWidth, ...)` so widget content does not resize the sidebar during refreshes.

## Tests

Run focused tests first:

```bash
swift test --filter ConfigTest
```

Then run the full suite when feasible:

```bash
swift test
```

Do not relaunch the app unless the user explicitly asks.
