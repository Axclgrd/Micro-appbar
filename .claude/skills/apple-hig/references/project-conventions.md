# Micro-app conventions (apply on top of the HIG)

- **Targets**: apps and Kits build for macOS 14. `trousse` targets macOS 26. Never raise a Kit/app minimum without the owner's say-so; wrap macOS 26 APIs in `if #available(macOS 26, *)` with a material fallback (see `liquid-glass-swiftui.md`).
- **Panels are written once** in `Kits/<X>Kit/` and displayed both by Trousse and by the standalone app (`MenuBarShell`: `NSStatusItem` + `NSPopover`, width 300). Change the panel in the Kit, never in the app.
- **Shared design pieces live in `Kits/Commun`** (shared tokens/components). Add there, don't duplicate per Kit.
- **Windows** (Purge, Bande) are real windows (`ToolWindow`: titled, `fullSizeContentView`, transparent titlebar, hidden title).
- **Language**: UI strings and code comments in French. Comments explain *why*, in the repo's existing voice.
- **Polling**: panels poll only while open (`activate()` / `idle()`); animations must not keep a closed panel busy.
- **Build**: `cd <app> && swift build -c release` to check; `./build.sh --install` replaces the installed app and relaunches it.
- **Rollback**: git tag `avant-design` is the pre-redesign state; the redesign lives on branch `design-apple`.
