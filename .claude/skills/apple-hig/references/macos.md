# macOS reference (HIG) for menu bar utilities and small windows

Audience: an engineer building small macOS utilities, mostly menu bar extras (MenuBarExtra, LSUIElement) or small windows.
Source: Apple Human Interface Guidelines, base URL `https://developer.apple.com/design/human-interface-guidelines/<topic>`. Quotes are verbatim from the HIG pages; "Note" lines are mine and flag where the HIG is silent. Nothing here goes beyond the sources except the SwiftUI mapping lines.

Topics cited: designing-for-macos, the-menu-bar, menus, windows, sidebars, toolbars, popovers, panels, sheets, settings, alerts, split-views, scroll-views, going-full-screen, launching, dock-menus, pointing-devices, keyboards, drag-and-drop, file-management, notifications, managing-notifications, onboarding, feedback, loading, modality, privacy, context-menus. `status-bars` is iOS/iPadOS only ("Not supported in macOS"), so ignore it.

---

## 0. Mac mindset (designing-for-macos)
Source: https://developer.apple.com/design/human-interface-guidelines/designing-for-macos

- Assume a large display, a viewing distance of about 1 to 3 feet, and keyboard + pointing device used together.
- People keep many apps open and expect "smooth transitions between active and inactive states as they switch from one app to another."
- Leverage large displays "to present more content in fewer nested levels and with less need for modality."
- Let people resize, hide, show and move windows. Use the menu bar for "all the commands they need." Handle keyboard shortcuts. Support personalization (customizable toolbars, window configuration, colors, fonts).

SwiftUI mapping: `WindowGroup`/`Window` for windows, `.commands { }` for the menu bar, `.keyboardShortcut` for accelerators.

---

## 1. Menu bar and menu bar extras
Sources: https://developer.apple.com/design/human-interface-guidelines/the-menu-bar , https://developer.apple.com/design/human-interface-guidelines/dock-menus

### Menu bar extra rules (macOS section of the-menu-bar)
- A menu bar extra "exposes app-specific functionality using an icon that appears in the menu bar when your app is running, even when it's not the frontmost app." Extras sit on the trailing side, opposite your app's menus.
- The menu bar's height is **24 pt**.
- Use a symbol: "Consider using a symbol to represent your menu bar extra" (a custom icon or an SF Symbol). Both use black and clear colors so "the system can apply other colors to the black areas ... so it looks good on both dark and light menu bars, and when your menu bar extra is selected." So: draw template (monochrome) art, never fixed colors.
- **Display a menu, not a popover**, when people click the extra. Verbatim: "Unless the app functionality you want to expose is too complex for a menu, avoid presenting it in a Popovers." Default to a menu. Use a popover-like panel only when the content genuinely cannot be a menu (sliders, live graphs, text input, rich status).
- **Let people decide** whether the extra is in the menu bar. Verbatim: "Typically, people add a menu bar extra to the menu bar by changing a setting in an app's settings window. To ensure discoverability, however, consider giving people the option of doing so during setup."
- **Do not rely on its presence.** "The system hides and shows menu bar extras regularly, and you can't be sure which other menu bar extras people have chosen to display or predict the location of your menu bar extra." The system hides extras when space is tight. Never make the extra the only way to reach a function.
- **Expose functionality elsewhere too:** "you can provide a Dock menu ... People can hide or choose not to use your menu bar extra, but a Dock menu is always available when your app is running."
- Menu titles in the menu bar: "Prefer short, one-word menu titles" (title-style capitalization if more than one word). The system may shrink spacing and truncate titles when space is constrained.

### Standard menus (if your utility has a normal app menu bar)
Order: *YourAppName*, File, Edit, Format, View, app-specific menus, Window, Help (Apple menu is system-owned, can't be modified).
- Support the default system menus and their ordering. "Always show the same set of menu items": disable, never hide, unavailable items.
- App menu order: About (put a separator after it, alone in its group; app name 16 characters or fewer, no version number), Settings…, optional app-specific items (after Settings, same group), Services, Hide *App*, Hide Others, Show All, Quit *App*. Option turns Quit into "Quit and Keep Windows". Use the same short app name for About, Hide and Quit.
- Settings… in the app menu is for app-level settings only. Document-specific settings go in File.
- View menu: provide it "even if your app supports only a subset of the standard view functions" (e.g. only Enter/Exit Full Screen). Show/hide titles must reflect state (Show Toolbar / Hide Toolbar). It does not manage windows.
- Window menu: "Provide a Window menu even if your app has only one window", with Minimize and Zoom so Full Keyboard Access users can invoke them. List open windows alphabetically; avoid listing panels or other modal views.
- Help menu: keep the number of items small. Use a separator between primary help and extras.
- App-specific menus: put custom commands in the menu bar even if they exist elsewhere. This makes them findable, shortcut-able and Full Keyboard Access reachable. Order from most to least general or commonly used.
- Dynamic menu items (change with a modifier key): never the only way to do a task; mostly in menu bar menus (not context or Dock menus); one modifier only.
- Use the same icons as the system for Copy, Share, Delete (see Standard icons).
- Keep standard shortcuts for standard items (Copy, Cut, Paste, Save, Print). Define custom ones "only when necessary."

### Dock menu (dock-menus)
- Secondary click (Control-click) on the Dock icon shows system + custom items.
- "Make custom Dock menu items available in other places, too" (menu bar menus or in-UI). Prefer high-value items: current/recent windows, plus a few actions useful when the app isn't frontmost or has no windows (Mail: get new mail, compose).
- Note: a Dock menu only matters if the app has a Dock icon. An LSUIElement app has none, so the HIG's "a Dock menu is always available" fallback does not apply; the menu itself must be your robust surface.

SwiftUI mapping: `MenuBarExtra("Title", systemImage: "name") { ... }` with `.menuBarExtraStyle(.menu)` for the HIG-preferred menu, or `.menuBarExtraStyle(.window)` for a panel when a menu is too limited. `MenuBarExtra(isInserted: $binding)` (bind it to a Settings toggle, per "let people decide"). Menu-bar commands via `.commands { CommandMenu("Name") { ... } ; CommandGroup(replacing:/after:) { ... } }`. Hide the Dock icon with Info.plist `LSUIElement = YES` (not an HIG item). Dock menu is AppKit: `applicationDockMenu(_:)`.

---

## 2. Windows and panels
Sources: https://developer.apple.com/design/human-interface-guidelines/windows , https://developer.apple.com/design/human-interface-guidelines/panels , https://developer.apple.com/design/human-interface-guidelines/going-full-screen

### Windows
- Primary window = main navigation + content. Auxiliary window = one specific task; "doesn't allow navigation to other app areas, and it typically includes a button people use to close it after completing the task." A small utility window is an auxiliary window.
- "Avoid creating custom window UI." No custom frames or controls: "Doing so without perfectly matching the system's look and behavior can make your app feel broken."
- Choose when to open a new window. "Avoid opening new windows as default behavior unless it makes sense for your app." Offer "view in a new window" in a context menu or File menu.
- Say "window" in user-facing text, never "scene".
- macOS window states: **Main** (frontmost, one per app), **Key** (accepts input, one onscreen), **Inactive**. The system changes title-bar colors and removes Materials for inactive windows; custom windows must use the system-defined appearances.
- Avoid critical info or actions in a bottom bar ("people often relocate a window in a way that hides its bottom edge"). If you must, show only a small amount of information related to content (Finder's status bar). Use an inspector for more.
- Windows should adapt fluidly to different sizes.

### Panels (NSPanel-style utility windows)
- "A panel typically floats above other open windows providing supplementary controls, options, or information related to the active window or current selection." Less prominent than a window.
- Use for quick access to controls/info about current content; consider for inspector functionality (an inspector auto-updates with the selection; an "Info" window with fixed contents must be a regular window).
- "Prefer simple adjustment controls": sliders and steppers over typing/selecting.
- Title: brief noun or noun phrase, title-style capitalization ("Fonts", "Colors", "Inspector"). Panels need a title bar so people can position them. In menus use the title without "panel" ("Show Inspector").
- Show/hide: when the app becomes active, bring all open panels to the front; when inactive, hide all of them.
- Keep panels out of the Window menu's document list (show/hide commands are fine). "In general, avoid making a panel's minimize button available."
- HUD-style panels: dark and translucent. "Prefer standard panels." Use HUD only in media-oriented apps, when a standard panel would obscure essential content, or when you need no controls (most system controls don't match a HUD). Keep one panel style across modes, use color sparingly, keep HUDs small.

### Full screen
- Support it only "when it makes sense" (games, media, in-depth tasks). For a small utility, usually skip it.
- "Use the system-provided full-screen experience" (handles the camera housing on some Macs).
- "Always let people choose when to enter full-screen mode": window button, View menu item, or Control-Command-F. Avoid a custom window-modes menu.
- Don't programmatically resize the window in full screen. Let people reveal the Dock. Let people choose when to exit; resume where they left off after switching away.

SwiftUI mapping: `Window("Title", id:) { }` for a single-instance utility window, `WindowGroup` for multi-instance; `.windowResizability(.contentSize)` to lock size to content; `.defaultSize(width:height:)`; `.windowToolbarStyle`. Open with the `openWindow` environment action. Floating panels and HUDs are AppKit: `NSPanel`, `hudWindow` style mask. Full screen: `NSWindow.toggleFullScreen(_:)`.

---

## 3. Popovers, sheets, alerts and modality
Sources: https://developer.apple.com/design/human-interface-guidelines/popovers , https://developer.apple.com/design/human-interface-guidelines/sheets , https://developer.apple.com/design/human-interface-guidelines/alerts , https://developer.apple.com/design/human-interface-guidelines/modality

### Modality (general)
- Use it "only when there's a clear benefit." Keep modal tasks "simple, short, and streamlined." Avoid "an app within your app": offer a single path, no buttons that look like the dismiss button.
- "Always give people an obvious way to dismiss a modal view." In macOS, people expect a button in the main content view.
- Confirm before closing if user-generated content would be lost. Give the modal a title or text naming its task.
- One modal at a time; dismiss one before presenting another. An alert may sit on top of anything, but never show more than one alert at a time.

### Popovers (transient, anchored)
- "Use a popover to expose a small amount of information or functionality" (a few related tasks). It disappears after the interaction.
- The arrow points as directly as possible at the revealing element; don't cover that element or essential content.
- Close button (Cancel/Done) only "for confirmation and guidance"; otherwise it closes on outside click or on selecting an item. With multi-select, keep it open until explicitly dismissed or an outside click.
- "Always save work when automatically closing a nonmodal popover." Discard only on an explicit Cancel.
- One popover at a time. No cascades. Nothing over a popover except an alert. Ideally switch from one popover to another with a single click.
- "Avoid making a popover too big." Animate size changes (condensed vs expanded) so it doesn't feel like a new popover replaced the old one.
- "Avoid using a popover to show a warning": "People can miss a popover or accidentally close it." Use an alert.
- macOS: a popover can be detachable (drag it out and it becomes a panel). Consider it, and keep the detached appearance nearly unchanged. Avoid the word "popover" in help text.
- Note (not in HIG): the HIG does not give a pt width for a popover or menu bar panel. Don't cite a "300 pt" Apple number; treat width as your own choice, "only big enough to display its contents".

### Sheets (macOS)
- A scoped task closely related to the current context. In macOS a sheet is always modal: a cardlike view with rounded corners floating on the parent window, which is dimmed.
- Present at a reasonable default size; people don't generally expect to resize sheets, but supporting resize is a good idea.
- Let people interact with other app windows before dismissing a sheet (bring the parent forward; other windows can be brought forward).
- Use a **panel** instead of a sheet "if people need to repeatedly provide input and observe results" (find and replace).
- For complex or prolonged flows, use a new window or full screen instead.
- One sheet at a time; if a sheet spawns another, close the first, then (optionally) show it again after.
- Buttons: **Cancel** dismisses without saving; **Done** completes/saves; **Back** goes to a previous step and is not for dismissing. If you provide Done, always pair it with Cancel or Back. "Avoid showing all three buttons."

### Alerts
- Use sparingly. They are modal, interrupt, and show a title, optional informative text, and **up to three buttons**. macOS adds an icon, accessory view, suppression checkbox, and Help button.
- Not for information only (put it in context instead), not for common undoable destructive actions (deleting a file), and "Avoid showing an alert when your app starts."
- Title: describes the situation specifically and succinctly (never just "Error"), not more than two lines. A full sentence uses sentence-style capitalization with ending punctuation; a fragment uses title-style capitalization and no ending punctuation.
- Buttons: one or two words, verbs related to the text ("View All", "Reply", "Ignore"). Sentence-style capitalization, no ending punctuation. "Always use 'Cancel'" to cancel. Don't use OK as the default unless purely informational (use "Erase", "Convert", "Clear", "Delete"). Default button on the trailing side/top of a stack; Cancel on the leading side/bottom.
- Destructive style only for a destructive action people did not deliberately choose (not for a deliberately chosen "Empty Trash"). Don't make Cancel the default.
- Allow Escape or Command-Period to cancel.
- macOS: the app icon shows by default. Use the caution symbol (`exclamationmark.triangle`) "sparingly", only when extra attention is needed, such as possible unexpected data loss, not for save or empty trash. Offer a suppression checkbox for repeating alerts.

SwiftUI mapping: `.popover(isPresented:attachmentAnchor:arrowEdge:content:)` (anchor to a control inside a window; for the menu bar extra panel use `MenuBarExtra` with `.window` style, not `.popover`), `.sheet(isPresented:)` / `.sheet(item:onDismiss:content:)`, `.alert(_:isPresented:actions:message:)`, `.confirmationDialog`, `.interactiveDismissDisabled()` to guard against accidental dismissal when work would be lost. Button roles: `Button(role: .cancel)` and `Button(role: .destructive)`.

---

## 4. Sidebars, split views, toolbars (for windowed utilities)
Sources: https://developer.apple.com/design/human-interface-guidelines/sidebars , https://developer.apple.com/design/human-interface-guidelines/split-views , https://developer.apple.com/design/human-interface-guidelines/toolbars , https://developer.apple.com/design/human-interface-guidelines/scroll-views

Most menu bar utilities need none of this. Use it only when a small window has real navigation.

### Sidebars
- Leading-side navigation between areas or top-level collections. "Show no more than two levels of hierarchy"; if deeper, add a content list in a split view. Use succinct group labels.
- Let people customize and hide it ("Avoid hiding the sidebar by default"). Provide a show/hide button or Show Sidebar / Hide Sidebar in the View menu.
- Use SF Symbols. Sidebar icons use the app accent color by default, and in macOS people may change the system accent color; honor it. Use fixed colors only sparingly and for a purpose.
- macOS sidebar size is small, medium or large, set in General settings by the user. Consider auto-collapsing when the window shrinks. "Avoid putting critical information or actions at the bottom of a sidebar."
- Extend visually rich content beneath the sidebar (a background extension effect) where the Liquid Glass layer floats.

### Split views
- Multiple adjacent panes; selecting an item in the primary pane shows it in the secondary one. "Persistently highlight the current selection in each pane that leads to the detail view."
- macOS: panes can be vertical, horizontal, or both, with draggable dividers. Set sensible min/max pane sizes so the divider stays visible. Allow hiding a pane and provide multiple ways to reveal it (toolbar button, menu command with shortcut). "Prefer the thin divider style" (1 pt). Consider drag and drop between panes.

### Toolbars
- Three content types: view title, navigation controls (and search), actions. Three areas: leading (back, sidebar toggle, title, document menu; not customizable), center (customizable; collapses into the system overflow menu), trailing (important items, inspector buttons, search, More menu, primary action; always visible).
- "Choose items deliberately to avoid overcrowding." Don't add the overflow menu manually; the system does in macOS. Add a **More** menu only if needed.
- At most about **three groups**. Separate text-labeled buttons with fixed space. Prefer SF Symbols without borders; text only where symbols fail (e.g. edit).
- `.prominent` style for one key action (Done/Submit), on the trailing side.
- Reduce custom toolbar backgrounds and tints. Use standard components (concentric corner radii).
- Titles: useful and concise, "under 15 characters". Don't title the window with your app name. Use the standard Back and Close symbols; no "Back"/"Close" text labels.
- **macOS rule: "Make every toolbar item available as a command in the menu bar"** (users can hide or customize the toolbar). Not every menu item needs a toolbar item.

### Scroll views
- Support default scrolling and keyboard shortcuts. Make scrollability apparent (show partial content at the edge). No nested scroll views with the same orientation.
- Scroll edge effect only when a scroll view is behind floating elements. Prefer the automatic style; one per view.
- macOS: scroll indicator = scroll bar; use small or mini scroll bars in a panel when space is tight, with the same size for all controls in the panel.

SwiftUI mapping: `NavigationSplitView { sidebar } detail: { }` (two-column) or three-column; `List(selection:)` with `.listStyle(.sidebar)`; `HSplitView`/`VSplitView` for macOS divider panes; `.toolbar { ToolbarItem(placement: ...) { } ; ToolbarItemGroup }` and `.navigationTitle`; `.inspector(isPresented:)` for the trailing inspector pane; `ScrollView`; `.scrollEdgeEffectStyle` for edge effects (newest OS only; check availability).

---

## 5. Settings window
Source: https://developer.apple.com/design/human-interface-guidelines/settings

- Defaults first: "provide default settings that give the best experience to the largest number of people." "Minimize the number of settings you offer."
- Put "general, infrequently changed settings" in the settings area. Task-specific options (show/hide parts of the view, reorder, filter) belong in the screens they affect, not Settings.
- Don't ask for setup info you can detect (e.g. Dark Mode). Don't duplicate system-wide settings (accessibility, scrolling, authentication).
- macOS specifics:
  - Include a Settings item in the **App menu** with **Command-Comma (,)**. "Avoid adding settings buttons to a window's toolbar." Document-level options go in File.
  - Dim the minimize and maximize (zoom) buttons.
  - Toolbar in the settings window: "noncustomizable toolbar that remains visible and always indicates the active toolbar button." Panes are chosen from it.
  - Update the title to the visible pane; with one pane the title is "*App Name* Settings".
  - Restore the most recently viewed pane.
- Utility tie-in: a Settings window is the natural home for "Show in menu bar" and "Launch at login"-style toggles (the menu bar extra guidance says the setting lives in settings).
- Notifications: "Make sure people can manage their notification settings within your app" (managing-notifications).

SwiftUI mapping: the `Settings { TabView { ... .tabItem { Label(...) } } }` scene gives the standard window, the App menu item, and Command-Comma for free; `@AppStorage` for persistence; `SettingsLink` and `@Environment(\.openSettings)` to open it from a menu or panel (needed for LSUIElement apps with no app menu).

---

## 6. Menus, context menus, keyboard shortcuts
Sources: https://developer.apple.com/design/human-interface-guidelines/menus , https://developer.apple.com/design/human-interface-guidelines/context-menus , https://developer.apple.com/design/human-interface-guidelines/keyboards

### Menu content (applies to the menu bar extra menu too)
- Label: verb or verb phrase; title-style capitalization; drop articles (a, an, the); dim unavailable items rather than hiding them; if all items are unavailable, the menu stays openable.
- Append an ellipsis (…) when the action needs more input before completing.
- Icons: sparingly and with purpose; "provide icons for all menu items in a group, or none of them"; use the standard system icons for Copy/Share/Delete.
- Order: important or frequent items first; group related items with separators (keep related commands together even if importance differs). Mind length: long only for user-generated lists (History/Bookmarks style).
- Submenus: sparingly, one level, about five items max ("if a submenu contains more than about five items, consider creating a new menu"); keep available even when children are unavailable. Prefer submenus over indentation. A repeated term in more than two items is a cue for a submenu.
- Toggled items: either one changeable label (Show Map / Hide Map), add a verb if ambiguous (Turn HDR On), or show both; checkmarks show attributes in effect; consider a "Plain"-style reset item.
- macOS menu width is automatic (widest item).

### Context menus
- Reveal via Control-click or secondary click. Hidden by default, so "Always make context menu items available in the main interface, too" (the menu bar lists all commands).
- Few, relevant items; consistent across the app; submenus one level; max about **three** separator groups.
- **Hide** unavailable items instead of dimming (exception: Cut/Copy/Paste may appear dimmed).
- Put keyboard shortcuts in main menus, not in context menus. Title rarely, only if it clarifies the scope. Most frequent items nearest where the menu appears (reverse order if it opens upward).
- Destructive-item red styling guidance is for iOS/iPadOS/visionOS; HIG doesn't give it for macOS.

### Keyboard shortcuts
- Support Full Keyboard Access. Respect standard shortcuts; "In general, don't repurpose standard keyboard shortcuts for custom actions" (only if the action makes no sense in your app, e.g. Command-I for Get Info if no italics).
- Standard ones most relevant to utilities: Command-Comma Settings, Command-Q Quit, Command-W Close window, Command-H Hide, Command-M Minimize, Command-N New, Command-O Open, Command-S Save, Command-P Print, Command-Z / Shift-Command-Z Undo/Redo, Command-C/X/V, Command-A, Command-F Find, Command-Period or Esc cancel, Command-Question mark Help, Control-Command-F full screen, Command-Grave next window in app, Option-Command-T show/hide toolbar, Option-Command-I inspector.
- Custom: "only the most frequently used app-specific commands." Command is the main modifier, Shift secondary, Option sparingly for less-common/power features, **avoid Control** (system uses it widely). Order when combined: Control, Option, Shift, Command. Don't add Shift to a shortcut on the upper character of a two-character key (Help is Command-Question mark, not Shift-Command-Slash). Don't make a shortcut by adding a modifier to an unrelated existing one. With non-Command modifiers use only alphabetic characters (not all keyboards have all symbols). The system localizes and mirrors shortcuts.

SwiftUI mapping: `Menu { } label: { }`; `Button("Title…") { }.keyboardShortcut("k", modifiers: [.command, .shift])`; `Toggle` in a menu renders a checkmark; `Divider()` as separator; `.contextMenu { }` (hide unavailable items with `if`, don't `.disabled`); `.disabled(_:)` in menu-bar menus; `CommandGroup`/`CommandMenu` for menu bar commands; `.help("…")` for tooltips.

---

## 7. Pointer, keyboard focus, drag and drop, files
Sources: https://developer.apple.com/design/human-interface-guidelines/pointing-devices , https://developer.apple.com/design/human-interface-guidelines/drag-and-drop , https://developer.apple.com/design/human-interface-guidelines/file-management

### Pointer
- Be consistent with mouse/trackpad gestures; "Avoid redefining systemwide trackpad gestures." Provide the same behavior across gestures, pointer, and keyboard; the same result when a modifier is held (e.g. Option-drag duplicates).
- Let the pointer reveal and hide auto-hiding controls.
- macOS click vocabulary: primary click selects/activates; secondary click reveals contextual menus; scrolling; smart zoom; swipe between pages. Standard cursors: arrow, open/closed hand (drag content), pointing hand (link), I-beam (text), crosshair (precise selection), resize cursors, drag copy (Option), drag link (Option+Command), disappearing item, operation not allowed, contextual menu (Control).
- The iPadOS pointer-effect and hit-region padding guidance (12 pt / 24 pt) is for iPadOS only; not for macOS.

### Drag and drop
- Support it where people will try it; text fields/views get it for free. Always "Offer alternative ways to accomplish drag-and-drop actions" (menu commands).
- Same container = move; different container = copy; between apps = always copy. Option at drop time forces a copy.
- Feedback: show a translucent drag image "as soon as people drag a selection about three points"; highlight valid destinations only while hovering; show "not allowed" (or nothing) for invalid; animate back or evaporate for failed drops; progress or placeholder for slow transfers.
- Offer multiple representations from highest to lowest fidelity; accept the richest one you can handle; extract only the relevant portion.
- macOS extras: drag out to the Finder in a format you can reopen (clippings for text); let people drag from an inactive window without activating it; consider a count badge for multi-item drags; change the pointer to indicate the result. Keep selection state correct after a drop. Prefer undo for drops.
- Utility tie-in: a menu bar panel that accepts dropped files must show clearly when it can accept them and what happened.

### Files
- Hide file extensions by default but let people show them. Autosave rather than requiring Save. Use the default file browser (open/save panels) "unless you have an important reason to create a custom one". Name a save panel's default "Untitled"; customizable Open button title.
- With autosave off, show unsaved state (dot on the close button).
- Quick Look: preview files your app can't open.

SwiftUI mapping: `.draggable(_:)`, `.dropDestination(for:action:isTargeted:)` (or `.onDrop(of:isTargeted:perform:)`), `.fileImporter`/`.fileExporter`, `DocumentGroup` for document apps, `.onHover { }` for hover state, `NSCursor` (AppKit) for pointer styles.

---

## 8. Notifications, feedback, loading
Sources: https://developer.apple.com/design/human-interface-guidelines/notifications , https://developer.apple.com/design/human-interface-guidelines/managing-notifications , https://developer.apple.com/design/human-interface-guidelines/feedback , https://developer.apple.com/design/human-interface-guidelines/loading

### Notifications
- Must "get their consent" before sending any. Permission can be changed in system settings.
- Concise and informative; one notification per event ("Avoid sending multiple notifications for the same thing"); don't tell people to perform tasks in the app; "Use an alert — not a notification — to display an error message"; no sensitive information.
- Title: short, title-style capitalization, no ending punctuation (if the title is generic, let the system show the app name). Body: complete sentences, sentence case, proper punctuation, don't truncate. Provide generic body text for hidden previews ("New comment"). Don't include your app name or icon in the content.
- Foreground handling: notifications don't show when the app is frontmost, so present the info unobtrusively (update the badge or the view).
- Sound is optional, "short, distinctive, and professionally produced"; never the only carrier of important information.
- Actions: up to **four** buttons; short title-case terms; skip an action that merely opens the app; prefer nondestructive.
- Badge: only for unread notification count; never the only method for essential info; keep it current; don't mimic a badge.
- Interruption levels: Passive, Active (default), Time Sensitive, Critical (needs entitlement). Time Sensitive only for things relevant "within an hour"; never for marketing. Marketing/promotional notifications need explicit opt-in and an in-app way to change the choice.

### Feedback
- Match the significance to the delivery: passive status in the UI, interruptions only for warnings that prevent data loss.
- Make all feedback accessible (combine color, text, sound).
- Integrate status near the items it describes. Alerts for critical, ideally actionable information. Warn only for "unexpected and irreversible" data loss, not for expected results (Finder trash). Confirm significant task completion only when it matters, since people expect success. Explain why a command can't be carried out.

### Loading
- "The best content-loading experience finishes before people become aware of it." Show something ASAP (placeholders), let people do other things while loading, use determinate indicators when duration is known and indeterminate when not ("Progress indicators").
- Utility tie-in: a menu bar panel should open with cached or placeholder data and fill in, not block on a spinner.

SwiftUI mapping: `UNUserNotificationCenter.current().requestAuthorization(options:)`, `UNMutableNotificationContent`, `UNNotificationAction`/`UNNotificationCategory`; `ProgressView()` (indeterminate) and `ProgressView(value:total:)` (determinate); `.redacted(reason: .placeholder)` for placeholders; `.alert` for errors.

---

## 9. Permissions and privacy prompts
Source: https://developer.apple.com/design/human-interface-guidelines/privacy

- "Request access only to data that you actually need" and make requests as specific as possible. Be transparent about use. Process on-device where possible.
- Things needing permission include personal data, user-generated content, protected resources (Bluetooth, Wi-Fi, local networks), and device capabilities (camera, microphone).
- **When:** "Request permission only when your app clearly needs access", ideally when the person uses the feature that needs it. "Avoid requesting permission at launch unless the data or resource is required for your app to function." If the app can't function without it, ask during onboarding (onboarding page agrees: in that case show why and the benefit).
- **Purpose string:** brief, complete, specific sentence; sentence case; active voice; ends with a period. Good: "The app records during the night to detect snoring sounds." Bad: "Microphone access is needed for a better experience." (passive, vague) and "Turn on microphone access." (imperative, no reason).
- **Pre-alert screen** (optional): exactly one button, titled "Continue" or "Next" (not "Allow"); no cancel/close option that skips the system alert (except for legal consent). Never mimic the system alert or annotate behind it; no incentives for tracking.
- Protecting data: use the keychain for sensitive data; never store passwords in plain-text files; no custom auth schemes (prefer passkeys, Sign in with Apple, Password AutoFill).
- macOS: sign with a valid Developer ID if distributing outside the store; use app sandboxing ("All apps submitted to the Mac App Store require sandboxing"); "Avoid making assumptions about who is signed in" (fast user switching).
- Note: the Location button is iOS/iPadOS/watchOS only; the HIG privacy page doesn't cover macOS-specific TCC flows such as Accessibility or Screen Recording; don't invent guidance for them. Apply the same principles: ask in context, explain why, handle denial gracefully (feedback page: show when a command can't be carried out and why).

SwiftUI mapping: no SwiftUI API; purpose strings are Info.plist `NS…UsageDescription` keys, requests go through the framework's authorization call (AVFoundation, CoreLocation, UserNotifications), keychain via Security framework, sandbox via App Sandbox entitlement.

---

## 10. Launching and onboarding
Sources: https://developer.apple.com/design/human-interface-guidelines/launching , https://developer.apple.com/design/human-interface-guidelines/onboarding

- "Launch instantly." People don't want to wait more than a couple of seconds. macOS doesn't require a launch screen (no launch screen work on Mac).
- "Restore the previous state when your app restarts": scroll position, windows in the same state and place.
- Onboarding occurs after launch, not part of it. Ideally unneeded. If needed, "fast, fun, and optional." Teach by interaction; prefer context-specific tips over one flow (TipKit); keep it about your app, not the system; make any tutorial skippable, not repeated on later launches, and findable later (help, account, or settings).
- "Postpone nonessential setup flows or customization steps." Provide reasonable defaults. Avoid licensing details in onboarding. Don't prompt for ratings or purchases before people have experienced the app.
- Menu bar utility tie-in (from the-menu-bar): offer "Show in menu bar" as a choice in setup/settings, since people decide whether the extra appears. Because the extra may be hidden by the system or by the user, a first-run hint pointing at the icon is in the spirit of "discoverability" but the HIG does not prescribe one.

SwiftUI mapping: `@AppStorage("hasSeenIntro")` to gate a one-time sheet or window; `.sheet`/`Window("Welcome", id:)` for first-run; `@SceneStorage` and automatic window state restoration for "restore previous state"; TipKit's `Tip` for contextual tips. Launch at login uses `SMAppService` (not an HIG item).

---

## Menu-bar-utility checklist (derived strictly from the sources above)

1. The extra's icon is a template symbol or icon (black + clear), reads on light and dark menu bars and when selected, and fits the 24 pt menu bar. (the-menu-bar)
2. Clicking the extra shows a menu unless the functionality is truly too complex for one; a panel is the exception, not the default. (the-menu-bar)
3. The menu bar extra's presence is controlled by the user (a Settings toggle, optionally offered at setup), not forced. (the-menu-bar)
4. No function is reachable only through the extra; the same commands exist in a Settings window, in-app UI, or Dock menu where one exists. (the-menu-bar, dock-menus)
5. Menu items: verb-first labels, title-style capitalization, no articles, ellipsis when more input is needed, unavailable items dimmed (not hidden) in the extra's menu. (menus)
6. Menu is short and grouped by separators with important items first; submenus are at most one level and about five items; icons are all-or-none within a group. (menus)
7. Toggles use a changeable label, a verb if ambiguous, or a checkmark for state. (menus)
8. If the panel is a popover-like view, it holds a small amount of functionality, is only as big as its content, and nothing opens over it except an alert; no popover cascades. (popovers)
9. The panel saves user input when auto-dismissed by an outside click; it discards only on explicit Cancel; it never carries warnings (use an alert). (popovers)
10. Settings is a real Settings window reachable by Command-Comma and an App-menu Settings… item (provide an alternative entry point from the extra's menu); minimize/zoom dimmed; toolbar of panes; title tracks the pane or reads "App Name Settings"; last pane restored; few settings with good defaults. (settings, keyboards)
11. Custom shortcuts are rare, use Command (never Control) as the main modifier, list modifiers in Control-Option-Shift-Command order, and never override standard shortcuts like Command-Q, Command-W, Command-Comma. (keyboards)
12. Standard Quit and (if windows exist) Window/Minimize/Zoom exist so keyboard-only users can reach them; Full Keyboard Access works. (the-menu-bar, keyboards)
13. Destructive or confirm dialogs use alerts sparingly: specific title, verb button titles, "Cancel" present, Cancel not default, Escape/Command-Period dismiss; no alert at app start. (alerts)
14. Auxiliary windows use system chrome (no custom frames), have a close path, and don't put critical actions in a bottom bar; sheets are one at a time with Cancel/Done pairing. (windows, sheets, modality)
15. Permission requests happen in context when the feature is first used (not at launch unless required), with a one-sentence active purpose string; any pre-alert has a single "Continue" button. (privacy, onboarding)
16. Notifications are opt-in, concise, deduplicated, free of sensitive info, never used for errors (use an alert), with an in-app way to manage them; badge only for unread counts. (notifications, managing-notifications)
17. Loading shows cached or placeholder content immediately, never blocks the panel on a spinner; progress is determinate when duration is known. (loading, feedback)
18. Feedback is passive and in-context for status, accessible beyond color alone, warns only about unexpected, irreversible loss, and explains why a command can't run. (feedback)
19. Drag-and-drop targets (if any) show valid vs invalid state only while hovering, have a non-drag alternative, and show progress for slow transfers. (drag-and-drop)
20. First launch is instant, the app restores its prior state, onboarding is optional and brief, and defaults work with no setup. (launching, onboarding)
