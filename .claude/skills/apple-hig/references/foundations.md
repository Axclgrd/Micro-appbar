# Apple HIG Foundations (macOS primary, iOS secondary)

Condensed from the verbatim HIG pages in `sources/`. Rules stay close to Apple's wording; numbers are Apple's. visionOS, watchOS and tvOS material is dropped. Where a rule is platform-specific it is tagged [macOS] or [iOS/iPadOS]. Untagged rules apply to both.

Known gap in the sources: the iOS/iPadOS Dynamic Type size table and the iOS tracking table are empty in the captured page. Do not guess them; read them in Apple Design Resources or the live page.

---

## 1. Design principles
Source: https://developer.apple.com/design/human-interface-guidelines/design-principles

Use these to weigh competing priorities, not as a checklist.

- **Purpose.** Create value: ask what the product is for and whether the design serves it. Keep focused: prioritize the most important features and make them great. Find new ways to solve the problem rather than re-creating existing solutions.
- **Agency.** Stay out of the way: get people directly to the task or content. Let people explore without being locked into flows or modes; when a guided flow is necessary, make it easy to skip or escape. Help people recover from mistakes: make reversing an action or returning to a previous state easy.
- **Responsibility.** Be fully transparent about what the product does and why. Give a clear rationale when asking permission and say what data you collect and how you use it. Collect only what the product needs, handle it with care, and anticipate misuse.
- **Familiarity.** Use concepts people know from the real world and other software. Keep visuals and interactions consistent: once a behavior or appearance is established for an element, apply it everywhere. Provide clear feedback: show when controls are available, indicate when content changes, use system patterns for alerts and choices.
- **Flexibility.** Design for everyone; treat accessibility as a priority from the start. Preserve context across platforms and configurations: keep content and controls in consistent, predictable positions and use natural animations to ease transitions. Support many input methods (voice, touch, keyboard, more). Approach every platform with intention, with the same level of care for each.
- **Simplicity.** Include just what is necessary; simplicity is not minimalism. Be concise in words and labels. Establish hierarchy so form and function are readily apparent.
- **Craft.** Quality sets the tone: be deliberate with visuals, animations, wording, audio. Prototype early, iterate, test in real-world settings. Shipping is not the finish line; keep up with platform capabilities and design patterns.
- **Delight.** Identify the emotion you want to inspire. Every interaction (button press, error message) can carry character. Do not mistake delight for decoration: do not let it get in the way of the core purpose. Delight is the sum of freedom to act, safety to explore, familiar metaphors, and flexibility across contexts.

SwiftUI mapping: prefer standard components (they carry platform behavior and feedback); `UndoManager` via `@Environment(\.undoManager)` backs "help people recover"; one SwiftUI codebase still needs per-platform layout decisions (`#if os(macOS)`).

---

## 2. Color
Source: https://developer.apple.com/design/human-interface-guidelines/color

**Principles**
- Do not use the same color to mean different things. Example: if brand color marks a borderless button as interactive, do not use that color for noninteractive text.
- All colors must work in light, dark, and increased-contrast contexts. Prefer system colors (they define all variants). For a custom color supply light and dark variants plus an increased-contrast option for each. Even if the app ships in a single appearance, provide both light and dark colors so Liquid Glass can adapt.
- Test under varied lighting (bright surroundings look darker/more muted; dark environments look brighter/more saturated), on different devices (True Tone), and under P3 and sRGB display profiles (System Settings > Displays).
- Consider how artwork and translucency affect nearby colors (colors look different behind or on a translucent toolbar).
- If people choose colors, use the system color picker.

**Inclusive color**
- Never rely solely on color to differentiate objects, indicate interactivity, or communicate essential information. Add text labels or glyph shapes.
- Avoid colors that make content hard to perceive (insufficient contrast, color-blind-indistinguishable pairs).
- Consider cultural meaning of colors (red means danger in some cultures, positive in others).

**System colors**
- Do not hard-code system color values; documented values are reference only and change by release. Use APIs.
- Dynamic system colors are semantic (defined by purpose: backgrounds at hierarchy levels, labels, links, separators). Do not redefine their meaning: do not use the separator color as text, or secondary label color as a background.
- System hues: red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown. iOS grays: systemGray through systemGray6 (SwiftUI `gray` = systemGray).

**[iOS/iPadOS] backgrounds and foregrounds**
- Two background sets: system (`systemBackground`, `secondarySystemBackground`, `tertiarySystemBackground`) and grouped (`systemGroupedBackground`, `secondarySystemGroupedBackground`, `tertiarySystemGroupedBackground`). Use grouped for grouped table views, otherwise system.
- Hierarchy: primary for the overall view; secondary for grouping content within it; tertiary for grouping within secondary elements.
- Foreground: `label`, `secondaryLabel`, `tertiaryLabel`, `quaternaryLabel`, `placeholderText`, `separator` (lets underlying content show), `opaqueSeparator`, `link`.

**[macOS] dynamic system colors (AppKit names)**
- Text: `labelColor` (primary), `secondaryLabelColor` (subheadings/extra info), `tertiaryLabelColor`, `quaternaryLabelColor` (e.g. watermark text), `textColor` (document text), `placeholderTextColor`, `linkColor`, `headerTextColor` (table header cell), `controlTextColor`, `disabledControlTextColor` (unavailable control), `windowFrameTextColor` (title bar).
- Backgrounds: `windowBackgroundColor`, `controlBackgroundColor` (large element such as browser or table), `textBackgroundColor`, `underPageBackgroundColor` (behind document content), `alternatingContentBackgroundColors` (alternating rows/columns).
- Selection: `selectedContentBackgroundColor` (key window), `unemphasizedSelectedContentBackgroundColor` (non-key window), `selectedTextBackgroundColor`, `unemphasizedSelectedTextBackgroundColor`, `selectedTextColor`, `unemphasizedSelectedTextColor`, `alternateSelectedControlTextColor` (text on selected list/table surface), `selectedControlColor`, `selectedControlTextColor`, `selectedMenuItemTextColor`.
- Other: `controlColor`, `controlAccentColor` (user's accent from System Settings), `separatorColor`, `gridColor`, `keyboardFocusIndicatorColor` (focus ring), `findHighlightColor`, `highlightColor`, `shadowColor`.
- **App accent color (macOS 11+):** specify an accent color to customize buttons, selection highlighting, sidebar icons. It applies only when the user's General > Accent color is *multicolor*; otherwise the user's chosen color replaces yours. Exception: a sidebar icon with a fixed color you specify is not overridden.

**Liquid Glass color**
- Liquid Glass has no inherent color; it takes color from the content behind it. You may tint some elements (stained glass look) to emphasize a primary action; this is how prominent buttons work.
- Small elements (toolbars, tab bars) adapt between light and dark appearance; symbols and text default to monochrome (darker over light content, lighter over dark). Larger elements (sidebars) appear more opaque for legibility.
- Apply color sparingly to the material and to symbols/text on it; reserve for elements that benefit from emphasis (status indicators, primary actions). To emphasize a primary action, color the background, not the symbol or text. Do not add color to the background of multiple controls.
- With a colorful background, prefer monochromatic toolbars/tab bars or an accent color with sufficient differentiation; avoid similar colors in control labels. In apps with monochromatic content, brand color as accent color works well.
- In the content layer, avoid overlap of similar colors between content and controls; the resting state (e.g. top of a scroll view) must stay legible.

**Color management**
- Apply color profiles to images; sRGB is accurate on most displays. Use wide color (Display P3, 16 bits per channel, PNG) where it adds value. Provide sRGB/P3-specific variants in the asset catalog if similar P3 colors are indistinguishable or gradients clip on sRGB.

SwiftUI mapping: `Color.primary`, `Color.secondary`; hierarchical styles `.foregroundStyle(.secondary / .tertiary / .quaternary)`; system hues `Color.red ... Color.brown`, `Color.mint/.teal/.cyan/.indigo`; custom colors via Color Set assets (Any/Dark/High Contrast) and `Color("Name")`; `.tint(_:)` and the AccentColor asset; macOS semantic colors via `Color(nsColor: .labelColor)` etc.; iOS via `Color(uiColor: .secondarySystemBackground)`; `@Environment(\.colorSchemeContrast)`; `ColorPicker`.

---

## 3. Dark Mode
Source: https://developer.apple.com/design/human-interface-guidelines/dark-mode

- Do not offer an app-specific appearance setting; follow the systemwide one. People also use Auto, which can switch while your app is running.
- Ensure the app looks good in both appearances. Only in rare cases (e.g. immersive media viewing) use a permanently dark appearance.
- Test legibility with Increase Contrast and Reduce Transparency on (separately and together). Increase Contrast in Dark Mode can reduce contrast between dark text and a dark background.
- Dark palette: dimmer backgrounds, brighter foregrounds. Colors are not simply inverted; many are, some are not.
- Use semantic colors that adapt (`labelColor`, `controlColor` on macOS; `separator` on iOS). For a custom color add a Color Set asset with bright and dim variants. Avoid hard-coded or non-adaptive colors.
- **Contrast: at minimum 4.5:1 between colors; for custom foreground/background strive for 7:1, especially for small text.**
- Soften white backgrounds in content images (slightly darken) so they do not glow in Dark Mode.
- Icons and images: use SF Symbols wherever possible (dynamic colors or vibrancy). Design separate light/dark interface icons if necessary (e.g. full moon needs a subtle dark outline on light, none on dark; an oil drop may need a slight border on dark). Use the same asset if it works in both, otherwise adjust or provide separate light/dark assets combined in an asset catalog.
- Text: use system label colors (primary, secondary, tertiary, quaternary). Use system views for text fields and text views (they handle vibrancy automatically).
- **[iOS/iPadOS]** Two background sets, *base* (dimmer, recedes) and *elevated* (brighter, advances). The system switches base to elevated for popovers, modal sheets, multitasking apps, and multiple windows. Prefer system backgrounds; a custom background obscures these cues.
- **[macOS]** With the graphite accent color, window backgrounds pick up color from the desktop picture (*desktop tinting*). Add some transparency to custom component backgrounds so they pick up this tint, but only for a component with a visible background or bezel, and only in a neutral (non-colored) state; transparency on a colored state makes its color fluctuate.

SwiftUI mapping: `@Environment(\.colorScheme)`; semantic colors/`ShapeStyle` hierarchy; Color Set assets; asset-catalog light/dark image variants; avoid `.preferredColorScheme(_:)` as an in-app appearance setting.

---

## 4. Typography
Source: https://developer.apple.com/design/human-interface-guidelines/typography

**Legibility**
- Default / minimum sizes: **iOS/iPadOS 17 pt / 11 pt; macOS 13 pt / 10 pt.** Applies to custom and system fonts.
- Avoid light weights. Prefer Regular, Medium, Semibold, or Bold; avoid Ultralight, Thin, Light (hard to see, especially small). With a thin custom font, go larger than the recommended sizes.
- Test legibility in different contexts; if hard to read, increase size, increase contrast, or use system fonts.

**Hierarchy**
- Use weight, size, and color to emphasize important information; keep the relative hierarchy when text sizes change.
- Minimize the number of typefaces.
- Prioritize important content on text-size change (e.g. tab titles in a tabbed window should not grow).

**System fonts**
- San Francisco (SF Pro; also Compact, Mono, Arabic, Armenian, Georgian, Hebrew; rounded variants available) and New York (NY, serif). Variable fonts with dynamic optical sizes: you do not need discrete Text/Display sizes. Weights Ultralight to Black; SF has widths including Condensed and Expanded.
- SF Symbols use matching weights, so symbols and adjacent text align at any size.
- Use built-in text styles (weight, point size, and leading per style). They give Dynamic Type support where available. Modify via symbolic traits (e.g. bold) or leading: *loose leading* for wide columns/long passages, *tight leading* for height-constrained areas (list rows). If showing **three or more lines, avoid tight leading** even when height is limited.
- Do not embed system fonts; use `Font.Design` constants (`default` = system font, `serif` = New York).
- In mockups, adjust tracking by point size; the running system font adjusts tracking dynamically.

**Custom fonts**
- Must be legible (follow minimum sizes) and must implement the same accessibility behaviors as system fonts (Dynamic Type, Bold Text).

**[macOS] system font**
- SF Pro. **macOS does not support Dynamic Type.** NY is available only for Mac Catalyst.
- Use dynamic system font variants to match standard controls: control content (`controlContentFont(ofSize:)`), label (`labelFont`), menu (`menuFont`), menu bar (`menuBarFont`), message (`messageFont`), palette (`paletteFont`), title (`titleBarFont`), tool tips (`toolTipsFont`), document text (`userFont`), monospaced document text (`userFixedPitchFont`), `boldSystemFont`, `systemFont`.

**[macOS] built-in text styles (weight, size / line height in pt, emphasized weight)**

| Style | Weight | Size / Line | Emphasized |
|---|---|---|---|
| Large Title | Regular | 26 / 32 | Bold |
| Title 1 | Regular | 22 / 26 | Bold |
| Title 2 | Regular | 17 / 22 | Bold |
| Title 3 | Regular | 15 / 20 | Semibold |
| Headline | Bold | 13 / 16 | Heavy |
| Body | Regular | 13 / 16 | Semibold |
| Callout | Regular | 12 / 15 | Semibold |
| Subheadline | Regular | 11 / 14 | Semibold |
| Footnote | Regular | 10 / 13 | Semibold |
| Caption 1 | Regular | 10 / 13 | Medium |
| Caption 2 | Medium | 10 / 13 | Semibold |

Emphasized variants come from symbolic traits (SwiftUI `bold()`); emphasized weight may be medium, semibold, bold, or heavy.

**[macOS] tracking (size pt: 1/1000 em / pt)** for mockups and custom text: 10: +12 / +0.12; 11: +6 / +0.06; 12: 0; 13: -6 / -0.08; 14: -11 / -0.15; 15: -16 / -0.23; 16: -20 / -0.31; 17: -26 / -0.43; 18: -25 / -0.44; 20: -23 / -0.45; 22: -12 / -0.26; 24: +3 / +0.07; 26: +8 / +0.22; 28: +14 / +0.38; 30: +14 / +0.40; 34: +12 / +0.40; 40: +10 / +0.37; 48: +8 / +0.35; 60: +4 / +0.26; 72: +2 / +0.14; 80 and up: 0.

**[iOS/iPadOS]** SF Pro is the system font; NY is available. Dynamic Type and larger accessibility sizes are supported (size table not captured in sources; see gap note above).

**Supporting Dynamic Type [iOS/iPadOS]**
- Verify the layout adapts to all sizes; test with Larger Accessibility Text Sizes (Settings > Accessibility > Display & Text Size > Larger Text).
- Increase meaningful interface icon size with font size (SF Symbols scale automatically).
- Minimize truncation: aim to show as much useful text at the largest accessibility size as at the largest standard size. Avoid truncating in scrollable regions unless a separate view shows the rest. Let labels use as many lines as needed.
- Adjust layout at large sizes: stack text above secondary items (glyphs, timestamps); reduce column count in multicolumn text.
- Keep information hierarchy consistent (primary elements stay toward the top).

SwiftUI mapping: `Font.TextStyle`: `.largeTitle .title .title2 .title3 .headline .subheadline .body .callout .footnote .caption .caption2` via `.font(.body)`; `.bold()`; `.fontWeight(_:)`; `.font(.system(.body, design: .serif))` (`Font.Design`: `.default .serif .rounded .monospaced`); `.lineSpacing(_:)`; `.leading(.loose / .tight)` on Font; `@ScaledMetric` for custom sizes; `@Environment(\.dynamicTypeSize)` with `.isAccessibilityCategory`; `ViewThatFits` or `AnyLayout` to restack at large sizes; `.lineLimit(nil)`; custom fonts via `Font.custom(_:size:relativeTo:)`. macOS: `NSFont.systemFont(ofSize:)`, `NSFont.userFixedPitchFont(ofSize:)`.

---

## 5. Layout
Source: https://developer.apple.com/design/human-interface-guidelines/layout

**Visual hierarchy**
- Order content by importance: top and leading side first (reading order top-to-bottom, leading-to-trailing). Prefer standard components so right-to-left adapts automatically.
- Align elements to ease scanning; use indentation to convey hierarchy (aligned items read as related, indented as subordinate).
- Group related items with negative space, container shapes, or separator lines.
- Use progressive disclosure (disclosure triangles, menus, nested views, scrollable sections) to reduce initial content.
- Differentiate controls from content: use Liquid Glass for controls on supporting platforms. Instead of a solid or semi-opaque background beneath controls, use a **scroll edge effect** to elevate controls above content. Extend full-screen background content underneath sidebars, toolbars, and tab bars. If a sidebar or inspector would cover important parts of a background image, use a *background extension effect* (flips and blurs the image beneath adjacent components).

**Adaptability**
- Adapt to display size, orientation, window size, multitasking, external display, Display Zoom, text-size changes, locale (LTR/RTL, date/time/number formats, text length). Respect system safe areas, margins, and guides. Even a locked-orientation app must resize well.
- Be ready for text-size changes: stack horizontally adjacent views, grow rows/containers, allow multiple lines.
- Preview on multiple devices, size classes, localizations, and text sizes; test the largest and smallest layouts first.
- When scaling background artwork for different aspect ratios, do not change its aspect ratio; scale to fill.

**[iOS/iPadOS] size classes**
- Each dimension is *compact* or *regular*. Decide layout by size class, not device type or orientation. Consider all combinations.
- Keep functionality the same as size classes change; change only how much is visible. Larger spaces can switch tab bar to sidebar or expose overflow-menu items. Keep layout recognizable for the platform when resized.

**Guides and safe areas**
- Layout guides give standard margins and restrict text width for readability. A safe area is the region not covered by hardware features or window chrome (toolbar, tab bar, status bar); respect it so system UI (e.g. Dynamic Island) does not obstruct content.

**[macOS]**
- Avoid placing controls or critical information at the bottom of a window (windows are often moved partly below the screen edge).
- Avoid displaying content behind the camera housing at the top edge of the window.

SwiftUI mapping: `@Environment(\.horizontalSizeClass)` / `verticalSizeClass`; `NavigationSplitView` (sidebar), `TabView`; `.safeAreaInset(edge:)`, `.ignoresSafeArea()` for background extension under chrome; `.scrollEdgeEffectStyle(_:for:)` (scroll edge effect) and `.backgroundExtensionEffect()`; `ViewThatFits`, `Grid`, `LazyVGrid`; `.layoutDirection`; `.padding()` default system margins; `.frame(minWidth:)` for resizable macOS windows.

---

## 6. Materials and Liquid Glass
Source: https://developer.apple.com/design/human-interface-guidelines/materials

A material creates depth, layering, and hierarchy between foreground and background by letting color pass through. Two kinds: **Liquid Glass** and **standard materials**.

**Liquid Glass (functional layer)**
- It forms a distinct functional layer for controls and navigation (tab bars, sidebars) that floats above the content layer. Content scrolls and peeks through while controls stay legible.
- **Do not use Liquid Glass in the content layer.** Use standard materials for content-layer elements such as app backgrounds. Exception: controls in the content layer with a transient interactive element (sliders, toggles) take on a Liquid Glass appearance when activated.
- **Use Liquid Glass effects sparingly.** Standard system components pick it up automatically. On a custom control, apply it sparingly and only to the most important functional elements; overuse distracts from content.
- Two variants, both subject to system settings (user's preferred Liquid Glass look, Reduce Transparency, Increase Contrast):
  - **Regular:** blurs and adjusts luminosity of background to keep text and foreground legible; most system components use it. Use when background content may cause legibility issues or the component has a lot of text (alerts, sidebars, popovers). Scroll edge effects further enhance legibility.
  - **Clear:** highly translucent; **only for components over visually rich backgrounds** such as photos and video, for immersion. For legibility: if underlying content is bright, consider a **dark dimming layer at 35% opacity**; if sufficiently dark, or if using AVKit standard playback controls (which dim themselves), no dimming layer is needed.
- Color on Liquid Glass: see section 2.
- The HIG page gives no explicit rule on stacking glass on glass; do not assume one.

**Standard materials (content layer)**
- Use standard materials and effects (blur, vibrancy; `NSVisualEffectView` on macOS) to give structure to the content beneath Liquid Glass.
- Choose materials by semantic meaning and recommended usage, not by the color they appear to impart (system settings change appearance).
- Use system-defined vibrant colors on top of materials, whichever material you choose.
- Thicker (more opaque) materials give better contrast for fine text; thinner (more translucent) materials keep context visible.

**[iOS/iPadOS]** Standard materials: ultra-thin, thin, regular (default), thick. Vibrancy: labels `label` (default), `secondaryLabel`, `tertiaryLabel`, `quaternaryLabel` (avoid quaternary on thin and ultraThin: contrast too low); fills `fill` (default), `secondaryFill`, `tertiaryFill`; one default separator vibrancy.

**[macOS]** Standard materials have designated purposes, with vibrant versions (`NSVisualEffectView.Material`). Choose when to allow vibrancy in custom views and test in varied contexts. Choose a blending mode that fits: *behind window* or *within window* (`NSVisualEffectView.BlendingMode`).

SwiftUI mapping (principles only; Liquid Glass API details live in another file): standard materials `.ultraThinMaterial .thinMaterial .regularMaterial .thickMaterial .ultraThickMaterial`; `.background(.regularMaterial)`; vibrant text via hierarchical `.foregroundStyle(.secondary)`; macOS wrapping `NSVisualEffectView` via `NSViewRepresentable`; `@Environment(\.accessibilityReduceTransparency)`.

---

## 7. SF Symbols
Source: https://developer.apple.com/design/human-interface-guidelines/sf-symbols

Use a symbol to convey an object or concept wherever interface icons can appear (toolbars, tab bars, context menus, inline in text). Availability depends on OS version. Do not use symbols (or confusingly similar images) in app icons, logos, or other trademarked uses.

**Rendering modes**
- **Monochrome:** one color for all layers.
- **Hierarchical:** one color, different opacity per layer level (primary, secondary, tertiary) for depth.
- **Palette:** two or more colors, one per layer. Two colors on a three-level symbol means secondary and tertiary share one.
- **Multicolor:** intrinsic colors that enhance meaning (leaf is green, trash.slash is red).
- Use system-provided colors so symbols adapt to accessibility and appearance modes. Verify the mode works in every context; check where "automatic" is less legible.
- **Gradients** (SF Symbols 7+): smooth linear gradient from a single color, works in all modes; best at larger sizes.
- **Variable color:** represents a changing value (capacity, strength) by coloring layers as thresholds between 0 and 100% are reached. Use it to communicate change, not depth; use Hierarchical for depth. Some layers can opt out (the speaker body in `speaker.wave.3`).

**Weights and scales**
- Nine weights (ultralight to black) match SF font weights; match symbol weight to adjacent text.
- Three scales: small, medium (default), large, relative to SF cap height. Scale changes emphasis without breaking weight matching with same-point-size text.

**Design variants**
- Outline (most common), fill, slash, and enclosed (circle/square/rectangle); enclosed and slash can combine with outline or fill. Slash = unavailable; fill = selection.
- Outline: toolbars, lists, beside text. Enclosed: legibility at small sizes. Fill: more emphasis; good for tab bars, swipe actions, and accent-colored selection.
- Often the container picks the variant (iOS tab bar prefers fill; toolbar takes outline), so do not specify it unless needed.
- Many script/language-specific variants adapt automatically to device language.

**Animations** (SF Symbols 5+; work in all rendering modes, weights, scales, and custom symbols)
- Appear, Disappear; Bounce (once by default; action occurred or needs to); Scale (persists until changed; selection feedback); Pulse (opacity, ongoing activity); Variable color (cumulative or iterative; progress/ongoing activity; open vs closed loop symbols); Replace (down-up = state change; up-up = forward progression; off-up = emphasizes next state); Magic Replace (default replace; related shapes, e.g. slashes draw on/off; falls back to down-up for unrelated symbols); Wiggle (draw attention to a possibly overlooked change/call to action); Breathe (opacity and size; ongoing activity such as recording); Rotate (task in progress; By Layer for e.g. fan blades); Draw On / Draw Off (SF Symbols 7+; progress such as a download).
- Apply animations judiciously, with a clear purpose, matching app tone. Too many overwhelm and distract.

**Custom symbols**
- Export the template; match system symbols in detail, optical weight, alignment, position, perspective. Be simple, recognizable, inclusive, directly related to the action/content.
- Annotate layers (color or hierarchy level) in the SF Symbols app; needed for animation by layer. Test with all animation presets; draw whole shapes (use erase layers for cutouts).
- Use negative side margins (`left-margin-Regular-M` naming) for optical alignment of badged symbols.
- Avoid baking common variants (enclosures, badges) into custom symbols; use the component library.
- Provide alternative text (accessibility descriptions) for VoiceOver.
- Symbols depicting Apple products/features (badged with an Info icon in the app) cannot be customized; do not design replicas of Apple products.

SwiftUI mapping: `Image(systemName:)`, `Label("Title", systemImage:)`; `.symbolRenderingMode(.monochrome / .hierarchical / .palette / .multicolor)`; `.foregroundStyle(a, b, c)` for palette; `.symbolVariant(.fill / .slash / .circle / .square)`; `.imageScale(.small / .medium / .large)`; `.fontWeight(_:)` and `.font(_:)` to match text; `.symbolEffect(.bounce / .pulse / .variableColor / .scale / .wiggle / .breathe / .rotate, value:)` (some effects need newer OS); `.contentTransition(.symbolEffect(.replace))`; `Image(systemName:variableValue:)` for variable color; `.accessibilityLabel(_:)` on custom symbol images; macOS `NSImage(systemSymbolName:accessibilityDescription:)`.

---

## 8. Motion
Source: https://developer.apple.com/design/human-interface-guidelines/motion

System components include motion and adjust it for accessibility settings and input method (e.g. Liquid Glass responds with more emphasis to touch, more subdued with a trackpad). Follow these for custom motion.

- Add motion purposefully; do not add it for its own sake. Gratuitous animation distracts and can cause discomfort.
- **Make motion optional.** Never use motion as the only way to communicate important information; supplement with haptics and audio.
- Feedback motion should be realistic and follow gestures and expectations. If a view slides down from the top to reveal, it should not dismiss by sliding sideways.
- Be brief and precise: brief feedback feels lightweight and conveys information more effectively than prominent animation.
- In apps, generally avoid adding motion to frequent UI interactions; the system already animates standard elements.
- **Let people cancel motion.** Do not make them wait for an animation to finish before acting, especially if repeated.
- Consider animated SF Symbols (SF Symbols 5+).
- Games: aim for a consistent 30 to 60 fps with good default settings per platform; let people tune for performance or battery.
- Reduce Motion behavior is specified under Accessibility (section 9).

SwiftUI mapping: `withAnimation(_:)`, `.animation(_:value:)`, `.transition(_:)`, `.contentTransition(_:)`, `.symbolEffect(_:)`, `@Environment(\.accessibilityReduceMotion)` to swap movement for fades or skip animation; haptics via `.sensoryFeedback(_:trigger:)` on [iOS/iPadOS].

---

## 9. Accessibility
Source: https://developer.apple.com/design/human-interface-guidelines/accessibility

An accessible interface is intuitive, perceivable (no single method for information), and adaptable. Audit with Accessibility Inspector; declare support via App Store Accessibility Nutrition Labels.

**Vision**
- Support larger text: ideally allow enlargement by **at least 200%** (via Dynamic Type or custom UI).
- Default / minimum text sizes: iOS/iPadOS 17 / 11 pt; macOS 13 / 10 pt. Thin custom fonts need larger sizes.
- **Contrast (WCAG AA, as used by Accessibility Inspector):** text up to 17 pt, all weights: **4.5:1**; 18 pt, all weights: **3:1**; bold, all sizes: **3:1**. If not met by default, provide a higher-contrast scheme when Increase Contrast is on. Check both light and dark. (WCAG and APCA are the standard measures.)
- Prefer system-defined colors (accessible variants adapt automatically).
- Convey information with more than color alone (red-green and blue-orange are problematic); add shapes or icons; consider letting people customize chart colors.
- Describe the interface and content for VoiceOver.

**Hearing**
- Do not communicate dialogue or crucial information through audio alone. Provide captions, subtitles, audio descriptions, transcripts as fitting, with customizable presentation.
- Pair audio cues with haptics, and augment audio with visual cues.

**Mobility**
- **Control sizes (default / minimum): iOS/iPadOS 44x44 pt / 28x28 pt; macOS 28x28 pt / 20x20 pt.**
- Spacing is as important as size: about **12 pt padding around elements with a bezel; about 24 pt around elements without a bezel** (measured from visible edges).
- Use the simplest gestures for frequent actions; avoid custom multifinger/multihand gestures. Offer alternatives to gestures (e.g. a button as well as swipe-to-dismiss).
- Support Voice Control (label elements appropriately), Siri and Shortcuts, VoiceOver, AssistiveTouch, Full Keyboard Access, Pointer Control, Switch Control.

**Speech**
- Allow keyboard-only navigation and interaction (Full Keyboard Access). Do not override system-defined or accessibility keyboard shortcuts. Support Switch Control.

**Cognitive**
- Keep actions simple; prefer familiar system gestures and behaviors over custom ones.
- Minimize time-boxed UI (auto-dismiss on a timer); prefer explicit dismissal.
- Do not autoplay audio/video without controls; consider a global opt-out. Respect Dim Flashing Lights for video.
- **Reduce Motion:** be cautious with fast-moving and blinking animations. When Reduce Motion is on, reduce automatic and repetitive animations (zooming, scaling, peripheral motion). Practices: tighten springs to reduce bounce; track animations directly with gestures; avoid animating depth changes in z-axis layers; replace x/y/z transitions with fades; avoid animating into and out of blurs.
- [iOS/iPadOS] Assistive Access: identify core functionality and remove noncritical workflows/UI; break multistep workflows into one interaction per screen; ask for confirmation twice for hard-to-recover actions (e.g. deleting a file).

SwiftUI mapping: `.accessibilityLabel(_:)`, `.accessibilityHint(_:)`, `.accessibilityValue(_:)`, `.accessibilityAddTraits(_:)`, `.accessibilityElement(children:)`; `@Environment(\.accessibilityReduceMotion)`, `\.accessibilityReduceTransparency`, `\.accessibilityDifferentiateWithoutColor`, `\.colorSchemeContrast`, `\.dynamicTypeSize`; `.frame(minWidth: 44, minHeight: 44)` with `.contentShape(Rectangle())` on iOS (28 on macOS); `.keyboardShortcut(_:)` and `.focusable()` for keyboard access; `@ScaledMetric`.

---

## 10. Writing
Source: https://developer.apple.com/design/human-interface-guidelines/writing

- **Voice:** know who you are talking to and keep a list of common terms for consistency. **Tone:** match the context (serious for a payment error, light for a reached goal).
- Be clear: check each word is needed; fewer words if possible; read aloud. Write for everyone: plain language, no jargon or gendered terms, with accessibility and localization in mind.
- Put the most important information first on each screen; split multiple ideas across screens.
- **Be action oriented:** active voice; label buttons and links with verbs ("Send", not "Let's do it!"). Avoid being cute. Never "Click here"; use descriptive link text ("Learn more about UX Writing"), which matters for screen readers.
- Build consistent language patterns. Pick capitalization rules (title case is more formal, sentence case more casual), one per UI element type, and apply consistently.
- Multi-step flows: start with "Get Started", use "Continue" or "Next" consistently, finish with "Done".
- Use possessive pronouns sparingly ("Favorites", not "Your Favorites"); if used, be consistent. **Avoid "we"** (unclear referent): "Unable to load content", not "We're having trouble loading this content."
- Describe gestures correctly per device (do not say "click" for touch; say "tap").
- **Empty states:** give clear next steps with a button or link; do not show crucial information that will disappear.
- **Errors:** prevent when possible; show close to the problem; avoid blame; say how to fix ("Choose a password with at least 8 characters", not "That password is too short"). Skip "oops!" and "uh-oh". If language cannot fix a common error, rethink the interaction.
- Choose the delivery method (notification, alert, action sheet) by urgency and context.
- Settings: label practically; if needed describe what it does when on (people infer off). Link directly to a setting rather than describing its location.
- Text fields: label all fields; use hint/placeholder text (e.g. "name@example.com"); show errors next to the field and instruct ("Use only letters for your name", not "Invalid name").

SwiftUI mapping: `Text(LocalizedStringKey)` / `String(localized:)` with String Catalogs; `Button("Send", action:)`; `Link("Learn more about UX Writing", destination:)`; `TextField("name@example.com", text:)` prompt; `.textCase(nil)`; `ContentUnavailableView` for empty states.

---

## 11. Inclusion
Source: https://developer.apple.com/design/human-interface-guidelines/inclusion

- Examine assumptions; an inoffensive app is not necessarily inclusive. Perspectives vary by age, gender identity, race and ethnicity, sexuality, physical and cognitive attributes (permanent, temporary, situational disabilities), language and culture, religion, education, opinions, social and economic context.
- **Welcoming language:** consider tone from different perspectives (avoid an academic tone that implies high education is required). Address people as *you/your*, not "the user"/"the player"; reserve *we/our* for your software or company. Define specialized terms, or use plain language. Replace colloquialisms (e.g. "peanut gallery", "grandfathered in") with plain wording. Consider carefully before including humor.
- **Approachable:** require no prior skill; present a clear, standard interface; provide onboarding that lets newcomers go step by step and others skip.
- **Gender:** avoid unnecessary gender references ("Subscribers can post recipes to your shared folder", not "his or her recipes"). Prefer customizable avatars/emoji/glyphs; use nongendered human imagery (SF Symbols `figure`/`person`). If gender is required (health, legal), offer options such as *nonbinary*, *self-identify*, *decline to state*, and optionally pronouns.
- **People and settings:** portray a range of characteristics and activities; avoid stereotypes (e.g. only male doctors, female nurses); avoid showing high affluence unless it makes sense; prefer familiar, relatable places and items.
- **Avoid stereotypes:** e.g. do not assume a narrow definition of "family"; avoid context-specific security questions (use "What's your favorite activity?", "What was the name of your first friend?", "What quality describes you best?").
- **Accessibility:** support VoiceOver, Display Accommodations, closed captioning, Switch Control, Speak Screen. Each disability is a spectrum; anyone can have temporary or situational disabilities. Avoid language using disability as a negative quality; use people-first wording; prioritize simplicity and perceivability.
- **Languages:** internationalize (languages and regions for date, time, money) then localize. Plain language, no unnecessary gender references, varied people, and no stereotypes ease localization. SF Symbols help (language-specific glyphs, LTR/RTL support). Verify color meanings per locale (e.g. white means grief in some places, purity in others).

SwiftUI mapping: String Catalogs and `Text` localization; `.environment(\.layoutDirection, .rightToLeft)` and `.environment(\.locale, ...)` in previews; `Date.FormatStyle` / `.formatted()` for locale-aware dates, times, numbers; SF Symbols for glyphs; `Image(systemName: "figure")` / `"person"` for generic people.
