---
name: apple-hig
description: Design and review native Apple-platform UI (SwiftUI/AppKit on macOS first, iOS/iPadOS second) according to Apple's Human Interface Guidelines and Liquid Glass. Use when building or restyling a macOS menu bar extra, popover panel, window, sheet, settings, sidebar, toolbar, control, app icon, or any SwiftUI view that should look and behave like a first-party Apple app — layout, spacing, typography, color, SF Symbols, materials, Liquid Glass (glassEffect, GlassEffectContainer, .glass button styles), motion, accessibility, dark mode, and UI copy. Not for web UI (use apple-design for CSS).
---

# Apple HIG — native macOS / iOS design

The references are distilled from Apple's own pages (HIG + SwiftUI docs), fetched verbatim into `sources/`. When a rule is unclear, grep `sources/hig-<topic>.md` rather than guess.

## Workflow

1. Identify the surface: menu bar panel, window, sheet/popover, settings, iOS screen. Read the matching reference (below). Read `references/liquid-glass-swiftui.md` before touching any glass/material code.
2. Prefer **system components over custom drawing**. Standard controls (Button, Toggle, Picker, List, Form, Table, Menu, ProgressView, Gauge, toolbar, NavigationSplitView) adopt the current look automatically when built with the current SDK. Custom backgrounds, borders and fake chrome are the main reason an app feels "not Apple".
3. Use **semantic** type, color and spacing: `.font(.headline/.body/.callout/.caption)`, `.primary/.secondary/.tertiary`, `Color.accentColor`, `.controlSize`, system materials. No hard-coded hex, no fixed font sizes except for display numerals.
4. Glass belongs to the **functional layer** (toolbars, sidebars, floating controls) — never to content cards, never glass-on-glass, always grouped in a `GlassEffectContainer`.
5. Check the result against the checklist below. If you cannot see it (no screenshot), say so.

## References

| File | Read when |
|---|---|
| `references/foundations.md` | Color, typography, layout/spacing, SF Symbols, materials, motion, dark mode, accessibility, writing |
| `references/macos.md` | Menu bar extras, windows, panels, popovers, sheets, sidebars, toolbars, settings, menus, shortcuts, permissions |
| `references/components.md` | Choosing and configuring controls (buttons, toggles, pickers, lists, progress, fields…) |
| `references/liquid-glass-swiftui.md` | Any `glassEffect`, `.glass` button style, material fallback, `#available(macOS 26, *)` |
| `references/app-icons.md` | App icon work (macOS/iOS layered icons) |
| `references/project-conventions.md` | Working in the Micro-app repo (targets, French copy, Kits layout) |

## Review checklist (apply to every screen)

- **Hierarchy**: one clear primary action per surface; secondary actions quieter; destructive actions never the default.
- **Native controls** only; control sizes consistent (`.controlSize(.small)` throughout a dense panel is fine, mixing is not).
- **Spacing** on a consistent rhythm (multiples of 4; 12–16 pt panel margins; align leading edges; related items closer than unrelated).
- **Type**: system font, semantic styles, at most 3 levels per panel; numbers that change use `.monospacedDigit()`.
- **Color**: system/semantic colors; accent used for state or the primary action, not decoration; works in light, dark, increased contrast.
- **Symbols**: SF Symbols with a consistent weight/rendering mode; every icon-only control has an accessibility label and help tooltip.
- **Materials**: content uses standard materials or none; glass only on floating/functional elements; fallback exists for macOS < 26.
- **Motion**: short, interruptible, purposeful; honors Reduce Motion; no decoration-only animation.
- **Accessibility**: labels, VoiceOver order, Dynamic Type/size scaling where supported, 4.5:1 contrast, keyboard operable with visible focus.
- **Copy**: short, sentence case, verbs for buttons, no jargon or exclamation marks, consistent terms; French strings in French projects.
- **macOS manners**: ⌘W / ⌘, / ⌘Q behave; menu bar panel dismisses on outside click; hover states and tooltips exist; no unprompted permission requests.
