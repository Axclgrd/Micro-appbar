# Liquid Glass in SwiftUI (macOS 26 / iOS 26+)

Sources: Apple "Adopting Liquid Glass", "Applying Liquid Glass to custom views", Glass / GlassEffectContainer / glassEffect(_:in:) / glassEffectID / glassEffectUnion API pages, HIG Materials, Landmarks sample. Everything below needs the macOS 26 / iOS 26 SDK; see "Availability & fallback" at the end.

## 1. What Liquid Glass is

- A dynamic material combining the optical properties of glass with fluidity. It blurs content behind it, reflects color and light of surrounding content, and reacts to touch and pointer interactions in real time.
- It forms a distinct functional layer for controls and navigation (tab bars, sidebars, toolbars) that floats above the content layer. Content scrolls and peeks through beneath it.
- Two variants (HIG Materials):
  - regular: blurs and adjusts luminosity of background to keep text legible. Most system components use it. Prefer it when there is much text (alerts, sidebars, popovers) or legibility risk.
  - clear: highly translucent; only for components floating over visually rich media (photos, video). If the content underneath is bright, consider a dark dimming layer at about 35% opacity.
- People can change the Liquid Glass look in settings or enable Reduce Transparency / Reduce Motion / Increase Contrast; these modify the effect. System components adapt automatically; test custom elements under these settings.

## 2. What you get for free (system components)

Rebuild with the latest Xcode/SDK and run on the latest OS; standard SwiftUI/UIKit/AppKit components adopt the material automatically and adapt to overlap and focus state:

- Bars: toolbars (items grouped, glass appearance), tab bars (float; can minimize on scroll in iOS; can adapt into a sidebar), sidebars (float in the glass layer).
- Sheets, popovers, action sheets, menus (menus adopt glass and use icons for common actions).
- Controls: sliders/toggles (knob turns to glass while interacting), buttons morph into menus/popovers; rounder shapes concentric with hardware/windows; new extra-large control size.
- Windows get rounder corners; lists/tables/forms get larger row height, padding and section corner radius; section headers use title-style capitalization instead of all caps.
- Scroll views get a default automatic scroll edge effect for legibility under bars.

Guidance for system-component adoption:
- Remove custom backgrounds/appearances in toolbars, tab bars, split views, sheets and popovers (including custom visual-effect views in a popover); they interfere with glass and the scroll edge effect.
- Do not hard-code control layout metrics; use standard spacing; avoid overcrowding or layering glass on glass.
- Use system colors (or custom colors with light/dark + increased contrast variants) in controls.
- Opt out temporarily: add the `UIDesignRequiresCompatibility` key to Info to keep the previous look when building with the new SDK.

## 3. Custom views: glassEffect(_:in:)

Signature: `func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`

The system renders a shape anchored behind the view with the Liquid Glass material and applies foreground effects over it. Default: `.regular` variant in a `Capsule`. The glass anchors to the view's bounds including padding.

```swift
// Default: regular glass, capsule shape
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()

// Alternate shape with corner radius (use for larger components that look odd as Capsule/Circle)
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect(in: .rect(cornerRadius: 16.0))

// Tinted (suggests prominence) and interactive (reacts to touch/pointer)
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect(.regular.tint(.orange).interactive())
```

`Glass` is the configuration struct: `.regular`, `.tint(_:)`, `.interactive(_:)` are shown in the sources; the HIG also refers to a `clear` variant ("For developer guidance, see clear"), i.e. `Glass.clear`. Chain them: `.glassEffect(.clear.interactive(), in: .circle)` (the `.clear` spelling follows the HIG reference; verify in Xcode).

Rules from the sources:
- Apply `glassEffect` AFTER the modifiers that affect the view's appearance/layout (padding, font, frame...); it captures the content to hand to the container.
- Use the same shape language across custom components for consistency.
- Use `interactive` on custom controls to get the same fluid response standard buttons have.

## 4. GlassEffectContainer(spacing:)

Combines multiple glass shapes into one rendered shape so they blend and morph into each other, and improves rendering performance. Use it whenever several nearby views carry glass.

- `spacing` sets when blending starts: the larger the value, the sooner shapes merge as they approach. A container spacing larger than the inner HStack/VStack spacing makes shapes blend at rest.
- Animating views in/out makes shapes morph apart or together as space changes.

```swift
GlassEffectContainer(spacing: 40.0) {
    HStack(spacing: 40.0) {
        Image(systemName: "scribble.variable")
            .frame(width: 80.0, height: 80.0)
            .font(.system(size: 36))
            .glassEffect()

        Image(systemName: "eraser.fill")
            .frame(width: 80.0, height: 80.0)
            .font(.system(size: 36))
            .glassEffect()
            // offset shows how glass effects react to each other in a container
            .offset(x: -40.0, y: 0.0)
    }
}
```

## 5. glassEffectID + @Namespace (morphing)

`func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View`

Use with `glassEffect` inside a `GlassEffectContainer`. Give each glass a unique ID in a `@Namespace`; SwiftUI animates shapes to/from each other on hierarchy changes. It only affects view-hierarchy transitions/animations.

```swift
@State private var isExpanded: Bool = false
@Namespace private var namespace

var body: some View {
    GlassEffectContainer(spacing: 40.0) {
        HStack(spacing: 40.0) {
            Image(systemName: "scribble.variable")
                .frame(width: 80.0, height: 80.0)
                .font(.system(size: 36))
                .glassEffect()
                .glassEffectID("pencil", in: namespace)

            if isExpanded {
                Image(systemName: "eraser.fill")
                    .frame(width: 80.0, height: 80.0)
                    .font(.system(size: 36))
                    .glassEffect()
                    .glassEffectID("eraser", in: namespace)
            }
        }
    }

    Button("Toggle") {
        withAnimation { isExpanded.toggle() }
    }
    .buttonStyle(.glass)
}
```

Transitions (`GlassEffectTransition`, applied with `glassEffectTransition(_:)`):
- `matchedGeometry`: default for effects added/removed within the container's spacing.
- `materialize`: for effects added/removed farther apart than the container spacing; also the simpler/custom option together with `withAnimation`.
- Use these consistently across the app.

## 6. glassEffectUnion(id:namespace:)

Makes several views contribute to ONE glass shape even at rest. Effects with the same shape, glass variant and union ID combine. Useful for dynamically created views or views outside an HStack/VStack.

```swift
@Namespace private var namespace
let symbolSet: [String] = ["cloud.bolt.rain.fill", "sun.rain.fill", "moon.stars.fill", "moon.fill"]

GlassEffectContainer(spacing: 20.0) {
    HStack(spacing: 20.0) {
        ForEach(symbolSet.indices, id: \.self) { item in
            Image(systemName: symbolSet[item])
                .frame(width: 80.0, height: 80.0)
                .font(.system(size: 36))
                .glassEffect()
                .glassEffectUnion(id: item < 2 ? "1" : "2", namespace: namespace)
        }
    }
}
```

## 7. Button styles

Prefer the built-in styles over hand-made glass buttons:

```swift
Button("Action") { }
    .buttonStyle(.glass)            // PrimitiveButtonStyle.glass: glass based on the button's context
Button("Primary") { }
    .buttonStyle(.glassProminent)   // prominent variant (not documented in the provided sources; verify in Xcode)
```

`.glass` can be applied to a button or to a view containing buttons. In tvOS it shows glass regardless of focus. `buttonBorderShape(_:)` only affects `bordered` / `borderedProminent` styles ("platter" shape), not a custom glass effect.

## 8. backgroundExtensionEffect()

Mirrors and blurs copies of a view into edges that have available safe area, so the content appears to extend under a sidebar or inspector without scrolling there. Typical use: hero image in the detail column of a `NavigationSplitView`. Use sparingly (ideally one instance; visual clarity and performance). The view is clipped so the copies do not overlap.

```swift
NavigationSplitView {
    // sidebar content
} detail: {
    ZStack {
        BannerView()
            .backgroundExtensionEffect()
    }
}
.inspector(isPresented: $showInspector) {
    // inspector content
}
```

Landmarks sample: apply it to an image that extends to the leading and trailing edges; add overlays (headline, button) AFTER the modifier so only the image extends under the sidebar/inspector.

## 9. scrollEdgeEffectStyle(_:for:)

Scroll views render an automatic edge effect that keeps bars/controls legible by obscuring content scrolling beneath them. System bars use it by default. Change it with:

```swift
ScrollView {
    LazyVStack {
        ForEach(data) { item in
            RowView(item)
        }
    }
}
.scrollEdgeEffectStyle(.hard, for: .all)
```

For a custom bar holding controls/text/icons over scrolling content, register those views with the scroll edge effect APIs so content stays legible (the Adopting guide names these APIs without showing code).

## 10. Concentric shapes

The sources state the principle only: hardware curvature informs nested elements, so use rounded shapes concentric with their container (controls, sheets, popovers, windows); standard toolbar buttons/fields already have corner radii concentric with the bar, and custom components in a bar must match. The Adopting guide references "these APIs" for concentric shapes but the text of the list is not included in the sources, so no code is given here. App icons are likewise concentric with hardware.

## 11. AppKit

`NSGlassEffectView`: "a view that embeds its content view in a dynamic glass effect" (macOS 26). The sources give no further API detail. For SwiftUI on macOS use `glassEffect`. `MenuBarExtra` (SwiftUI scene) with `.menuBarExtraStyle(.window)` renders a popover-like window from the menu bar icon; its content is standard controls, so rely on system styling instead of custom backgrounds:

```swift
MenuBarExtra("Utility App", systemImage: "hammer") {
    ScrollView { LazyVGrid(...) }
}
.menuBarExtraStyle(.window)
```

## 12. Performance

Too many containers, or many glass effects outside containers, degrade performance. Limit glass onscreen at once; combine custom effects in one `GlassEffectContainer`; profile with Instruments.

---

## Availability & fallback

All APIs above (`glassEffect`, `Glass`, `GlassEffectContainer`, `glassEffectID`, `glassEffectUnion`, `.glass` / `.glassProminent`, `backgroundExtensionEffect`, `scrollEdgeEffectStyle`, `NSGlassEffectView`) are macOS 26 / iOS 26 and later. The sources show standard materials (`Material`, `.regularMaterial`, `.ultraThinMaterial`; ultra-thin, thin, regular, thick) as the content-layer alternative. For apps that must also run on macOS 14-25, wrap glass in an availability check and fall back to a material (the wrapper below is a suggested pattern, not from the sources):

```swift
import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, iOS 26, *) {
            var glass: Glass = .regular
            if let tint { glass = glass.tint(tint) }
            if interactive { glass = glass.interactive() }
            self.glassEffect(glass, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)   // or .ultraThinMaterial for a lighter look
        }
    }
}

// Usage: apply after layout/appearance modifiers
Label("Flag", systemImage: "flag.fill")
    .padding()
    .adaptiveGlass(in: .rect(cornerRadius: 16))
```

Container and button fallbacks follow the same shape:

```swift
@ViewBuilder func glassGroup<C: View>(spacing: CGFloat, @ViewBuilder _ content: () -> C) -> some View {
    if #available(macOS 26, iOS 26, *) {
        GlassEffectContainer(spacing: spacing) { content() }
    } else {
        content()
    }
}

// Buttons
if #available(macOS 26, iOS 26, *) {
    Button("Toggle") { }.buttonStyle(.glass)
} else {
    Button("Toggle") { }.buttonStyle(.bordered)
}
```

Material fallback notes (Material page): it blurs only your app's own background, not what is behind the app window; foreground gets vibrancy unless you set a custom `foregroundStyle` (hierarchical styles like `.secondary` keep it).

### Pitfalls

- Do not use Liquid Glass in the content layer (app backgrounds, content cards). Use standard materials there. Exception: transient interactive controls like sliders/toggles that the system turns to glass while active.
- Do not put glass on glass: avoid overcrowding or layering Liquid Glass elements on top of each other. Group nearby glass in one `GlassEffectContainer` so shapes are rendered together (and blend/morph) instead of stacking independent glass layers. (The sources do not spell out the "glass cannot sample other glass" rationale; the container advice and the no-layering rule are what they state.)
- Use sparingly: only the most important functional elements; glass should draw attention to content, not to itself.
- Modifier order: apply `glassEffect` after layout and appearance modifiers (padding, font, frame).
- Do not stack custom backgrounds behind system bars, sheets and popovers; they interfere with the scroll edge effect and glass.
- Use `clear` only over visually rich media; add a dimming layer (about 35% black) over bright content.
- Container `spacing` larger than the inner stack spacing makes glass merge at rest; match them deliberately.
- Avoid same-colored content and controls (see HIG Liquid Glass color): prefer monochrome labels over colorful content, and keep resting-state legibility.
- Always give icon-only buttons an accessibility label; test Reduce Transparency, Reduce Motion, Increase Contrast.
- Check that `matchedGeometry` / `materialize` are used consistently; `glassEffectID` and `glassEffectTransition` only matter during hierarchy changes.
