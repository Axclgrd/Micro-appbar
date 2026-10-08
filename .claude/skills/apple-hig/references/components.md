# Components reference (controls, lists, progress, input, navigation)

Source: Apple Human Interface Guidelines. Quoted numbers and wording come from the HIG pages; base URL `https://developer.apple.com/design/human-interface-guidelines/<topic>`. SwiftUI lines are mappings, not HIG text; "(26)" marks APIs that need iOS/macOS 26 (Liquid Glass generation). Platform tags: **[mac]** macOS, **[iOS]** iOS/iPadOS.

## 0. Choose the right control

| You need to... | Use | Not this |
|---|---|---|
| Start an instantaneous action | Button | Toggle, segmented control |
| Turn one thing on/off (state of content or a view) | Toggle (switch in list row [iOS]; checkbox/switch [mac]) | Pop-up button |
| One of >2 mutually exclusive options, <= ~5 on Mac | Radio buttons [mac] | A long radio list |
| One of a flat list of mutually exclusive options, space limited | Pop-up button | Pull-down button |
| Commands related to a button's purpose (Add, Sort, More) | Pull-down button | Pop-up button |
| 2 to ~5-7 closely related choices/states, always visible | Segmented control | Pop-up button to switch tabs |
| Switch panes of related content in the window body [mac] | Tab view | Segmented control |
| Navigate top-level sections of an app [iOS] | Tab bar | Segmented control, toolbar actions |
| Medium-to-long list of values (dates, times) | Picker | Pull-down for long lists |
| Very large set of values | List / table (with index) | Picker |
| Short list of choices | Pull-down button | Picker |
| Pick a value in a continuous range | Slider | Stepper |
| Small +/- increments of a value shown elsewhere | Stepper (next to a field) | Slider |
| Wide range, exact value matters | Slider + text field + stepper | Slider alone |
| Show a value within a range (read-only) | Gauge (level indicator [mac]) | Progress bar, slider |
| Task with known duration | Determinate progress bar | Spinner |
| Task with unknown duration | Indeterminate indicator (spinner) | Static text |
| Small amount of editable text | Text field (secure field for secrets) | Text view |
| Large amount of text | Text view | Text field |
| Search a collection | Search field | Plain text field |
| Hide advanced details until relevant | Disclosure control | Modal for minor options |
| Read-only text | Label | Disabled text field |
| Tabular/hierarchical data, selection, sorting | List / table / outline view | Collection for text rows |

---

## 1. Buttons
HIG: /buttons. "A button initiates an instantaneous action." A button combines **style**, **content** (symbol, text, or both) and **role**.

**Rules**
- Hit region at least **44x44 pt** (visionOS 60x60 pt). Include enough space around a button to distinguish it.
- Always include a **press state** for a custom button.
- **Prominence:** use a prominent style for the most likely action in a view (system applies accent color to the background). Keep prominent buttons to **one or two per view**.
- Distinguish the preferred choice by **style, not size**: same-size buttons signal a coherent set; differently sized neighbors look confusing.
- Avoid a label color similar to content-layer backgrounds; with colorful content prefer the default monochromatic label (Liquid Glass color).
- Content: familiar action = familiar icon (e.g. `square.and.arrow.up` = share; SF Symbols). Use text when a short label is clearer: title-style capitalization, start with a verb ("Add to Cart").
- Tooltips appear on hover in macOS and visionOS (see Offering help).
- **Roles:** Normal (no meaning), **Primary** (default button, most likely choice), **Cancel**, **Destructive** (data destruction). Primary uses accent color; destructive uses system red.
- Assign primary to the button people are most likely to choose; when it responds to **Return**, confirming is quick, and in a sheet/editable view/alert the view can close on Return.
- **Never make a destructive button primary**, even if it is the most likely choice (people press prominent buttons without reading).

**[iOS]** A button can show an activity indicator for non-instant actions, optionally with a changed label ("Checkout" -> "Checking out...").

**[mac]**
- Push button is the standard type: text, symbol, icon or image; can be the default button; can be tinted. Use flexible-height push button only for tall/variable content (two lines of text, tall icon).
- Trailing **ellipsis** in the title when the button opens another window, view or app ("Edit...").
- Consider spring loading (drag items over + force click, Magic Trackpad).
- **Square (gradient) button:** symbols/icons, no text; acts on an adjacent view (add/remove rows); place within or beneath that view, never in the window frame/toolbar/status bar; no introductory labels.
- **Help button:** circular, question mark, system-provided; opens context-relevant help (else top level); **no more than one per window**; inside a view, not toolbar/status bar; no introductory text. Location: dialog with dismissal buttons = lower corner opposite the dismissal buttons, vertically aligned with them; dialog without dismissal buttons, and Settings window/pane = lower-left or lower-right.
- **Image button:** in a view, not window frame; about **10 pixels** padding between image and button edges; avoid system border; label goes below.

**visionOS (for reference):** sizes Mini 28 / Small 32 / Regular 44 / Large 52 / Extra large 64 pt; centers at least 60 pt apart; prefer circular/capsule; white fill + black content is reserved for the toggled state.
**watchOS:** inline buttons are capsules; prefer full-width buttons for primary actions; toolbar for corner buttons.

**Common mistakes:** three or more prominent buttons; different sizes to show hierarchy; destructive primary; custom button with no press state; square/help/image buttons in the toolbar; label that is vague ("OK") instead of a verb phrase; icon-only button with obscure icon.

**SwiftUI mapping:** `Button("Add to Cart") {}` + `.buttonStyle(.borderedProminent)` (primary) / `.bordered` / `.borderless` / `.plain`; `.buttonStyle(.glass)` and `.glassProminent` (26); `Button(role: .destructive)`, `Button(role: .cancel)`; `.keyboardShortcut(.defaultAction)` for Return, `.keyboardShortcut(.cancelAction)` for Esc; `.controlSize(.mini/.small/.regular/.large/.extraLarge)`; `.buttonBorderShape(.capsule)`; `.tint(_)`; macOS help button is AppKit (`NSButton` help bezel), no SwiftUI style assumed here; `ProgressView` inside label for in-button activity.

---

## 2. Toggles, checkboxes, radio buttons
HIG: /toggles. "A toggle lets people choose between a pair of opposing states, like on and off."

**Rules**
- Use for two opposing values affecting the state of content or a view. For choosing from a list, use a different component (pop-up button).
- Clearly identify what it affects; context usually suffices, on Mac a label may be added. A button that behaves like a toggle uses an icon and changes appearance (typically the background) with state.
- Make state differences obvious (fill, shape, checkmark/dot). **Do not rely solely on color.**

**[iOS]**
- Use the **switch style only in a list row**; no separate label needed (row content gives context).
- Change the default green only if necessary; keep enough contrast with the uncolored appearance.
- **Outside a list, use a button that behaves like a toggle**, not a switch (e.g. Phone's filter button gets a blue highlight when active). Do not add a label explaining the button's purpose.

**[mac]** Use switches, checkboxes, radio buttons in the **window body, not the window frame** (not toolbar/status bar).
- **Switch:** for settings you want to emphasize (more visual weight; can control a group of settings). In a grouped form a **mini switch** keeps row height consistent; regular switch for the primary setting, mini for subordinates. **Don't replace an existing checkbox with a switch.**
- **Checkbox:** small square; empty = off, checkmark = on, dash = mixed. Title on trailing side. Use instead of a switch for a **hierarchy of settings** (align on leading edge, indent). Show **mixed** state when a parent checkbox governs subordinates with differing states. Introduce a group with a label if the relationship is unclear (baseline aligned with first checkbox).
- **Radio buttons:** circular + label; groups of **two to five**; mutually exclusive. More than about five options -> pop-up button. Multiple selections -> checkboxes. A single on/off setting -> prefer a checkbox. Mixed state is rarely useful. Use consistent spacing horizontally (based on longest label).

**Common mistakes:** switch outside a list on iOS; switch in a Mac toolbar; replacing checkboxes with switches; communicating state with color alone; radio button list of 8+; single radio button for a boolean.

**SwiftUI mapping:** `Toggle("Wi-Fi", isOn: $on)` + `.toggleStyle(.switch)`; `.toggleStyle(.checkbox)` (macOS only); `.toggleStyle(.button)` for toggle-like buttons; mini switch via `.controlSize(.mini)` on macOS; radio group = `Picker(...).pickerStyle(.radioGroup)` (macOS only); tint with `.tint(_)`.

---

## 3. Pickers (including date pickers)
HIG: /pickers. "A picker displays one or more scrollable lists of distinct values that people can choose from."

**Rules**
- Use for **medium-to-long** lists. Short list -> pull-down button. Very large set -> list/table (adjustable height, can have an index).
- Use predictable, logically ordered values (hidden values must be guessable, e.g. alphabetized countries).
- **Avoid switching views to show a picker**; show in context, below/near the field, typically at the window bottom or in a popover.
- Minutes: default 60 values; interval can increase if it divides evenly into 60 (e.g. 0, 15, 30, 45).

**[iOS] Date picker styles:** Compact (button showing editable date/time in accent color, opens a modal view; use when space is constrained), Inline (time only: button with wheels; date/time: inline calendar), Wheels (scrolling wheels, keyboard entry), Automatic. **Modes:** Date; Time; Date and time; Countdown timer (hours and minutes up to 23:59; not available in inline or compact).
**[mac]** Two date picker styles: **textual** (limited space, specific date/time entry) and **graphical** (browse calendar, select a range, or clock face).
**watchOS:** wheels style driven by the Digital Crown.

**SwiftUI mapping:** `Picker("Country", selection: $c) { ... }` + `.pickerStyle(.menu / .inline / .wheel (iOS) / .segmented / .navigationLink (iOS) / .radioGroup (macOS))`; `DatePicker(...)` + `.datePickerStyle(.compact / .graphical / .wheel (iOS) / .field (macOS) / .stepperField (macOS))`, `displayedComponents: [.date, .hourAndMinute]`.

---

## 4. Sliders
HIG: /sliders. Horizontal track + thumb between minimum and maximum; track fills with color from minimum to thumb; optional left/right icons.

**Rules**
- Customize appearance if it adds value (track color, thumb image/tint, min/max icons).
- Min on the **leading** side, max on the **trailing** side (horizontal); min at bottom, max at top (vertical). RTL languages follow leading/trailing.
- For wide ranges, consider supplementing with a **text field** (exact value/entry) and a **stepper** (whole-value increments).
- **[iOS]** Don't use a slider for audio volume; use a volume view (Playing audio).
- **[mac]** Tick marks available (increase clarity/accuracy); labels on ticks optional; often labeling min and max is enough; label periodically for nonlinear scales; show a tooltip with the thumb value on hover. Give **live feedback** while dragging (e.g. Dock Size). Linear slider: thumb is a narrow lozenge. **Circular slider** for repeating values (rotation 0-360, or 1440 degrees = 4 spins). Introduce with a label: sentence-style capitalization, ends with a colon.
- **visionOS:** prefer horizontal. **watchOS:** +/- buttons on sides; custom glyphs if needed. **tvOS:** not supported.

**Common mistakes:** reversed direction; slider for volume on iOS; no way to enter an exact value on a wide range; no live preview on Mac when it is cheap.

**SwiftUI mapping:** `Slider(value: $v, in: 0...100, step: 1)` with `minimumValueLabel:`/`maximumValueLabel:` (iOS); pair with `TextField(value:format:)` and `Stepper`. Tick-mark slider support is newer API; verify availability before use (not confirmed here).

---

## 5. Lists and tables
HIG: /lists-and-tables. Rows in one or more columns; can be grouped/hierarchical; support selecting, adding, deleting, reordering.

**Rules**
- **Prefer text** in lists/tables. Widely varying item sizes or many images -> collection.
- Let people edit when it makes sense (reorder even if add/remove isn't possible). **[iOS]** people must enter edit mode before selecting items.
- Selection feedback: navigation tables **persistently highlight** the selected row; option lists highlight briefly then show a **checkmark**.
- Keep row text succinct; consider middle-ellipsis truncation to keep start and end recognizable; for long text list titles and show content in a detail view.
- Multicolumn: descriptive column headings, nouns/short noun phrases, **title-style capitalization**, no ending punctuation. Single-column without heading: use a label or header.
- Styles: **[iOS]** grouped style (headers, footers, extra space between groups); **[mac]** bordered style with alternating row backgrounds; watchOS elliptical.

**[iOS]**
- **Info button** (detail disclosure button) only to reveal more info about row content; **it isn't for navigation**; use a **disclosure indicator** to drill into subviews.
- **Avoid an index** in tables whose rows have trailing controls (disclosure indicators): trailing-side conflict.

**[mac]** Click a column heading to sort (click again to reverse); let people **resize columns**; consider **alternating row colors** in wide multicolumn tables; use an **outline view** (disclosure triangles) for hierarchical data.
**tvOS:** focused rows scale and round corners; don't add your own corner masks. **watchOS:** limit rows; keep detail views short for vertical page navigation.

**Common mistakes:** info button used as navigation; index plus trailing disclosure indicators; truncating the distinguishing end of a string; table for image-heavy content; no sort/resize on a data table in a Mac app.

**SwiftUI mapping:** `List` + `.listStyle(.plain / .grouped / .insetGrouped (iOS) / .sidebar / .inset)`; `Table(data) { TableColumn("Name", value: \.name) }` (macOS, iPadOS; sortable via `sortOrder:`); `.alternatingRowBackgrounds()` (macOS); hierarchical = `List(data, children: \.children)` or `OutlineGroup`; `.swipeActions`, `.onMove`, `.onDelete`, `EditButton`; `NavigationLink` row supplies the disclosure indicator.

---

## 6. Progress indicators
HIG: /progress-indicators. Transient indicators that the app isn't stalled. **Determinate** = well-defined duration (linear bar fills leading-to-trailing; circular fills clockwise). **Indeterminate** (activity indicator / spinner) = unquantifiable; macOS also has an indeterminate bar.

**Rules**
- **Prefer determinate** when possible (lets people decide to wait, restart, or abandon).
- Be accurate; even out the pace (90% in 5 seconds then 10% in 5 minutes feels deceptive).
- **Keep them moving**; a stationary indicator reads as stalled. If it stalls, explain the problem and what to do.
- Switch a bar from indeterminate to determinate when the duration becomes known. **Don't switch from circular (spinner) to bar.**
- Description: accurate, succinct; avoid vague terms like *loading* or *authenticating*.
- Use a **consistent location**.
- Let people halt: include **Cancel** when side-effect free; add **Pause** as well if interrupting has negative side effects (lost downloaded portion). Alert with confirm-or-resume when canceling loses progress.

**[iOS] Refresh control:** hidden until you drag down a view (typically a table). Still **perform automatic updates**; title only if it adds value (e.g. "last updated"), never to explain how to refresh.
**[mac]** Prefer a **spinner** for background operations or constrained space (inside a text field, next to a control). **Avoid labeling a spinner.**
**watchOS:** white by default; tint to change.

**Common mistakes:** indeterminate bar for a measurable task; spinner that morphs into a bar; label "Loading..."; no cancel for a long operation; progress that jumps and stalls.

**SwiftUI mapping:** `ProgressView()` (indeterminate spinner), `ProgressView(value: done, total: total)` (determinate bar), `.progressViewStyle(.linear)`, `.progressViewStyle(.circular)`; `.refreshable { }` on List/ScrollView; `ProgressView(label:currentValueLabel:)` for descriptions.

---

## 7. Text fields
HIG: /text-fields. Rectangular area to enter or edit **small, specific** pieces of text. Large amounts -> text view.

**Rules**
- Placeholder hint (e.g. "Email") disappears on typing, so also provide a separate label.
- **Secure text field** for sensitive data (passwords).
- Match field size to anticipated text; stack multiple fields vertically with consistent widths; keep enough space so each label clearly belongs to its field.
- Logical tab order (system does it automatically mostly).
- Validate when it makes sense: email = when switching to another field; username/password = before switching away.
- Use a number formatter for numeric data (decimal places, percent, currency); don't assume presentation (locale varies).
- Line breaks: clipped by default; can wrap by character/word or truncate with ellipsis at beginning, middle or end. Consider an **expansion tooltip** for clipped text.
- **[iOS]** show the appropriate keyboard type. Show a **Clear button** at the trailing end; leading end = purpose image, trailing end = extra features (e.g. bookmarks).
- **[mac]** Consider a combo box to pair text input with a list of choices.
- watchOS/tvOS: minimize text entry; prefer lists/buttons.

**Entering data** (/entering-data): get info from the system when possible; be clear about the data needed (prompt like "username@company.com" or label "Email"); prefill reasonable defaults; **never prepopulate a password field**; **offer choices instead of requiring text entry** (picker, menu); support drag and drop and paste; **dynamically validate** and give feedback right away; make required data obvious (Next/Continue enabled only after required input). **[mac]** expansion tooltip for truncated text.

**Common mistakes:** placeholder as the only label; long text in a single-line field; validation only after submit; prefilled password; free text where a picker would do.

**SwiftUI mapping:** `TextField("Email", text: $email)`, `SecureField`, `TextField(value: $n, format: .number)`; `.textFieldStyle(.roundedBorder)`; `.keyboardType(.emailAddress)` and `.textContentType(.emailAddress)` (iOS); `.onSubmit`; `@FocusState` + `.focused($f, equals:)`; `.submitLabel(.next)` (iOS); `TextEditor` for larger text.

---

## 8. Search fields
HIG: /search-fields. Editable text field with Search icon, Clear button, placeholder text; supports **scope bars** and **tokens**.

**Rules**
- Placeholder text to show what can be searched.
- **Start searching immediately as the person types** if possible.
- Show suggestions (recents before search; predictive while typing).
- Simplify results: most relevant first, categorize.
- **Scope bar** = filter among clearly defined categories; **default to a broader scope** and let people narrow. **Token** = encapsulated, selectable/editable search term that filters further terms; pair tokens with suggestions so people discover them.
- **[iOS] placement (three):** tab in a tab bar, toolbar (bottom or top), inline with content.
  - Search tab, *standard tab style*: landing page with suggestions/discovery. *Button appearance*: tap focuses field and shows keyboard immediately; returns to previous tab on exit; for fast resolution.
  - Toolbar: **bottom if there's room** (Settings, Mail, Notes); **top** when bottom content must stay uncovered or no bottom toolbar (Wallet).
  - Inline: when position next to the searched content strengthens the relationship; above the list; consider pinning to the top toolbar on scroll.
- **[iPadOS/mac]** (keep consistent across both): **trailing side of the toolbar** for common uses (split views, results in detail); **top of sidebar** to filter sidebar/navigation; **item in sidebar/tab bar** for a dedicated discovery area (Music, TV). In a dedicated area, focus the field immediately (except iPad with only a virtual keyboard). Account for window resizing.
- tvOS: provide suggestions. watchOS: tapping the field opens full-screen text input.

**Common mistakes:** requiring Return to search; scope defaulting to narrow; search buried in a menu on iOS; tokens without suggestions.

**SwiftUI mapping:** `.searchable(text: $q, placement: ..., prompt: "Search songs")`; `.searchSuggestions { }` with `.searchCompletion(_)`; `.searchScopes($scope) { }`; `.searchable(text:tokens:)` for tokens; `Tab(role: .search)` for a search tab (iOS 18+; the button-appearance behavior is 26); `.searchToolbarBehavior` (26, verify before use).

---

## 9. Segmented controls
HIG: /segmented-controls. Linear set of two or more segments, each functioning as a button; single choice, or on **macOS** single or multiple; can be **momentary** (actions without selection state, e.g. Reply/Reply all/Forward).

**Rules**
- Closely related choices affecting an object, state or view; good when grouping or visible selection state matters (grouping persists regardless of size).
- **Keep types consistent:** don't assign actions to segments in a selection control, and don't show selection state in an action control.
- Limit segments: **about five to seven** in a wide interface, **about five on iPhone**.
- Equal segment width; **text or images, not a mix**; similar content size; **nouns/noun phrases**, title-style capitalization; no introductory text needed with text labels.
- **[iOS]** switch between closely related subviews (e.g. Calendar's New Event vs reminder); for completely separate sections use a **tab bar**.
- **[mac]** Introductory text or labels below icon segments; tooltip per segment; in the **main window area use a tab view** instead; segmented controls are for toolbar or inspector; consider spring loading.
- tvOS: consider split view for filtering; avoid nearby focusable elements. visionOS: tooltip for icon segments. watchOS: not supported.

**Common mistakes:** 8+ segments; mixing icons and text; using it for top-level navigation; verbs as labels.

**SwiftUI mapping:** `Picker("View", selection: $s) { Text("Day").tag(0) ... }` + `.pickerStyle(.segmented)`; `.labelsHidden()` when a label would be redundant. Momentary behavior is AppKit (`NSSegmentedControl.SwitchTracking.momentary`) / UIKit `isMomentary`.

---

## 10. Labels
HIG: /labels. Static text people can read and often copy but not edit.

**Rules**
- Small amount of non-editable text. Editable small text -> text field; large text -> text view.
- **Prefer system fonts**; Dynamic Type supported by default; keep legible if customized.
- Four system label colors for relative importance: **Label** (primary), **Secondary** (subheading/supplemental), **Tertiary** (text describing an unavailable item or behavior), **Quaternary** (watermark text). iOS/iPadOS/tvOS/visionOS: `label`, `secondaryLabel`, `tertiaryLabel`, `quaternaryLabel`; macOS: `labelColor` etc.
- **Make useful label text selectable** (error message, location, IP address).
- watchOS: use system date/timer text components (auto-update).

**SwiftUI mapping:** `Text` and `Label("Title", systemImage: "star")`; `.labelStyle(.iconOnly / .titleOnly / .titleAndIcon)`; `.foregroundStyle(.primary / .secondary / .tertiary / .quaternary)`; `.textSelection(.enabled)`; `.font(.body)` etc. for Dynamic Type; `Text(date, style: .timer)` for self-updating time (watchOS/widgets).

---

## 11. Pop-up buttons
HIG: /pop-up-buttons. "A pop-up button displays a menu of mutually exclusive options." After choosing, the menu closes and the button updates to show the selection. Not in tvOS/watchOS.

**Rules**
- Flat list of **mutually exclusive options or states**. Use a **pull-down** instead if you need to offer actions, allow multiple selection, or include a submenu.
- Provide a **useful default** selection (the item most people want).
- Let people predict the options without opening: introductory label or a descriptive button label.
- Good when space is limited and not all options need to show at once.
- Include a **Custom** option for occasional extra items; explanatory text below the list can help.
- **[iPadOS]** In a popover or modal view, consider a pop-up button instead of a disclosure indicator for a small, well-defined set of options per list item.

**SwiftUI mapping:** `Picker("Sort by", selection: $s) { ... }` + `.pickerStyle(.menu)` (default in many contexts); menu content can be grouped with `Section`/`Divider`.

---

## 12. Pull-down buttons
HIG: /pull-down-buttons. "A pull-down button displays a menu of items or actions that directly relate to the button's purpose." After choosing, the menu closes and the action runs. Not in tvOS/watchOS.

**Rules**
- Commands/items directly related to the button's action (Add -> what to add; Sort -> attribute; Back -> choose a location). For non-command exclusive choices use a pop-up button.
- **Don't put all of a view's actions in one pull-down**; primary actions must stay discoverable.
- Menu length: list **a minimum of three items** to feel worthwhile (one or two -> buttons, toggles or switches); too many slows people.
- Menu title only if it adds meaning.
- **Destructive items:** menus show red text for actions you identify as destructive; choosing one shows an **action sheet (iOS) or popover (iPadOS)** to confirm or cancel.
- Interface icon after the label when it adds value (SF Symbols).
- **[iOS]** A **More** (ellipsis) pull-down for items without prominent positions: weigh space against discoverability. Touch-and-hold can also reveal a menu (Safari Tabs button).

**SwiftUI mapping:** `Menu("Add") { Button("Photo") {} ; Button("Folder") {} }`; `Menu { } label: { Label("More", systemImage: "ellipsis.circle") }`; `Button("Delete", role: .destructive)` for the red item; `Menu { } primaryAction: { }` for tap-primary/hold-menu; confirm with `.confirmationDialog`.

---

## 13. Disclosure controls
HIG: /disclosure-controls. Reveal and hide information related to specific controls or views.

**Rules**
- Hide details until relevant; **most-used controls on top and always visible**, advanced functionality hidden by default.
- **Disclosure triangle:** points **inward from the leading edge** when hidden, **down** when visible. Needs a **descriptive label** ("Advanced Options"). Used for outline/hierarchy (Finder list view) or advanced options (Keynote export).
- **Disclosure button:** points **down** when hidden, **up** when shown. Place it **near the content it reveals**; **no more than one per view** (e.g. macOS Save sheet next to "Save As").
- iOS/iPadOS/visionOS use SwiftUI `DisclosureGroup`. Not in tvOS/watchOS.

**SwiftUI mapping:** `DisclosureGroup("Advanced Options", isExpanded: $open) { ... }`; hierarchical lists via `List(data, children:)`.

---

## 14. Steppers
HIG: /steppers. Two-segment control to increase or decrease an incremental value; **it doesn't display the value itself**, so it sits next to a field showing it.

**Rules**
- Make the affected value obvious.
- Pair with a **text field** when large changes are likely (e.g. copies on a print screen).
- **[mac]** For large ranges, support **Shift-click** to change by more than the default increment (e.g. 10x).
- Not in watchOS/tvOS.

**SwiftUI mapping:** `Stepper("Copies: \(n)", value: $n, in: 1...99)`; or `Stepper(value: $n, in: 1...99) { }` beside a `TextField(value:format:)`.

---

## 15. Gauges (and level indicators)
HIG: /gauges. Displays a specific numerical value within a range, with optional context (min/max, gradient). Circular or linear path; **standard** = indicator at the value; **capacity** = fill that stops at the value. **Accessory** variants echo watchOS complications (iOS Lock Screen widgets). Not in tvOS.

**Rules**
- Succinct labels for the **current value and both endpoints** (VoiceOver reads visible labels).
- Consider a gradient to communicate purpose (red-to-blue for hot-to-cold).
- **[mac]** Level indicator: capacity (discrete or continuous), rating, or (rarely) relevance. Use **continuous** for large ranges (discrete segments get too small). Default fill is green; change it (or use tiered state) at significant levels (very low, very high, just past middle). Rating style: see Ratings and reviews.

**SwiftUI mapping:** `Gauge(value: v, in: 0...100) { Text("Temp") } currentValueLabel: { Text("\(v)") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }` + `.gaugeStyle(.linearCapacity / .accessoryCircular / .accessoryCircularCapacity / .accessoryLinear / .accessoryLinearCapacity)`; `.tint(Gradient(colors:))`. macOS level indicator: AppKit `NSLevelIndicator`.

---

## 16. Focus and selection
HIG: /focus-and-selection. Focus confirms which object an interaction targets; often focusing also selects. Not supported in iOS/watchOS.

**Rules**
- **Rely on system-provided focus effects**; custom only if absolutely necessary.
- **Don't change focus without interaction.** Exception: with a discrete directional input (keyboard, remote, controller) when the focused item disappears, move to a nearby remaining item; otherwise hide the indicator.
- Be platform-consistent: iPadOS/macOS full keyboard access means you only need to support focus for **content elements (list items, text fields, search fields)**, not buttons/sliders/toggles; tvOS must make every element focusable.
- Visual: iPadOS/macOS focused list items use white text on an accent-color highlight; unfocused use standard text on gray highlight.
- **Focus ring for text/search fields; highlight for lists/collections** (ring OK for fully-filling cell content such as a photo).
- **[iPadOS]** focus groups: Tab moves among groups (reading order, leading to trailing, top to bottom), arrow keys move within a group; halo (focus ring) effect customizable; give the **primary item** higher priority.
- tvOS: up to five states (unfocused, focused, pressed, selected, disabled) with Parallax and scale; avoid a pointer; in full-screen content gestures act on content. visionOS: hover effect for eyes is separate from focus.

**SwiftUI mapping:** `@FocusState` + `.focused($field)`; `.focusable()`; `.focusEffectDisabled()` (macOS 14+/iOS 17+, only if justified); `.defaultFocus`; `List(selection:)` for selection highlight.

---

## 17. Tab bars
HIG: /tab-bars. Navigate between **top-level sections**; preserves navigation state per section.

**Rules**
- **Navigation, not actions** (actions -> toolbar).
- Keep the tab bar visible when navigating (exception: a modal covering it).
- Use only as many tabs as needed; fewer is easier. For complex structures use a sidebar or a tab bar that adapts to a sidebar. **Avoid overflow tabs** (trailing becomes a **More** tab in iOS/iPadOS).
- **Don't disable or hide tab bar buttons** when content is unavailable; if a section is empty, explain why.
- Include labels (single words when possible); SF Symbols for icons, **prefer filled** symbols; icons above labels in compact, side by side in regular.
- Badge (red oval, white text with number or exclamation point) only for **critical** information.
- Avoid similar colors for tab labels and content-layer backgrounds (prefer monochromatic with colorful content); see Liquid Glass color.
- **[iOS]** Floats at the bottom on Liquid Glass; an attached accessory (Music MiniPlayer) can minimize inline on scroll down; may include a dedicated **search tab** at the trailing end.
- **[iPadOS]** Tab bar near the top; fixed, or convertible to a sidebar; to present only a sidebar use a navigation split view. Let people **customize** the tab bar; default list of **five or fewer**.
- **[mac]** No additional tab bar considerations (use sidebars/toolbars; for pane switching see tab views). tvOS: height 68 pt, top edge 46 pt, not changeable. visionOS: always vertical, symbol + short label per tab; watchOS unsupported.

**SwiftUI mapping:** `TabView { Tab("Home", systemImage: "house") { HomeView() } }` (iOS 18+); `.tabViewStyle(.sidebarAdaptable)` (iPadOS/iOS 18); `.badge(3)`; `Tab(role: .search)`; `.tabBarMinimizeBehavior(.onScrollDown)` and `.tabViewBottomAccessory { }` (26).

---

## 18. Tab views
HIG: /tab-views. **[mac only]** (not iOS/iPadOS/tvOS/visionOS) Multiple mutually exclusive panes in the same area, switched with a tabbed control on the top edge of the content area.

**Rules**
- Use for closely related content; controls in a pane affect only that pane.
- Tab labels: nouns or short noun phrases, **title-style capitalization**, describe pane contents.
- **Avoid a pop-up button to switch tabs** (two clicks, choices hidden); acceptable when there are too many panes.
- **No more than six tabs**; beyond that consider a pop-up button menu of view options.
- Inset with a margin of window-body area on all sides. The tabbed control can be hidden (programmatic switching); the content area can then be borderless, bezeled or line-bordered.
- iOS/iPadOS: consider a segmented control. watchOS shows tab views as page controls.

**SwiftUI mapping:** `TabView` with `Tab`/`.tabItem` (macOS renders tabbed panes); `TabView` + `.tabViewStyle(.page)` on watchOS/iOS paging.

---

## 19. Status bars
HIG: /status-bars. **[iOS/iPadOS only]** Top-edge system display (time, carrier, battery).

**Rules**
- **Obscure content under the status bar**: it's transparent by default, so keep it readable and don't imply content behind it is interactive. Prefer a **scroll edge effect** (blurred view behind it).
- Temporarily hide it for full-screen media (e.g. Photos), with a simple discoverable gesture (single tap) to bring it back.
- **Avoid permanently hiding** it.

**SwiftUI mapping:** `.statusBarHidden(_:)` (iOS); `.scrollEdgeEffectStyle(.soft, for: .top)` (26); `.toolbarBackground` / `.toolbarColorScheme` for bar contrast.

---

## Cross-cutting checklist
- One or two prominent buttons per view; style, not size, for hierarchy; destructive never primary; default button answers Return.
- Switch only in iOS list rows; checkboxes/radios/switches in the Mac window body, not the toolbar.
- Prefer determinate progress; never swap spinner for bar; offer Cancel.
- Tab bar = navigation only, never hide/disable tabs; segmented control = related subviews; tab view = Mac panes.
- Label every input beyond placeholder; secure field for secrets; never prefill passwords; validate early.
- Don't rely on color alone for state; keep 44x44 pt hit regions.
