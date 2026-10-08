# App icons (macOS and iOS/iPadOS)

Sources: HIG App icons, HIG Icons, Adopting Liquid Glass, Landmarks sample.

## Project note

These projects generate their app icons by code (scripts that render the layers/PNGs), not by hand in a design tool. Follow the rules below when writing the generator: produce square, unmasked, flat-edged layers or a 1024x1024 master, and let the system do masking and effects.

## Specifications

| Platform | Layout shape | After system masking | Layout size | Style | Appearances |
|---|---|---|---|---|---|
| iOS, iPadOS, macOS | Square | Rounded rectangle | 1024x1024 px | Layered | Default, dark, clear light, clear dark, tinted light, tinted dark |

- No additional platform considerations for iOS, iPadOS or macOS in the HIG; the same icon rules apply to all three (consistent design across platforms is required).
- Color spaces: sRGB (color), Gray Gamma 2.2 (grayscale), Display P3 (wide gamut; iOS, iPadOS, macOS, tvOS, watchOS).
- The system scales the icon to produce smaller variants (Settings, notifications, etc.).
- Exact grid geometry is in the app icon production templates / updated grids from Apple Design Resources; the sources give no numeric grid beyond the 1024 px canvas. Keep primary content centered.

## Shape and masking (done by the system)

- Icons are square; the system applies the rounded-rectangle mask, with corners that match the curvature of other rounded UI elements and the device bezel (concentric).
- Provide square, unmasked layers. Pre-masked layers hurt specular highlights and give jagged edges.
- Keep primary content centered to avoid truncation when the system adjusts corners. Irregularly shaped icons receive a system-provided background.

## Layers and Liquid Glass style

- You can supply a flattened image, but layers give the most control. iOS, iPadOS and macOS icons have a background layer plus one or more foreground layers; the system adds Liquid Glass attributes (specular highlights, refraction, translucency, shadow, blur) and they adapt to icon size and system version.
- Use Icon Composer (in Xcode, also from Apple Design Resources) to import layers, define the background (solid color or gradient, so custom background images are rarely needed), place foreground layers, set opacity, group layers, tune Liquid Glass effects for groups, annotate default/dark/mono variants, preview across system versions, and export for Xcode. Drag and drop exported layers into it.
- Decide which elements are foreground, middle and background and make a layer for each (Landmarks uses four layers).
- Foreground layers: clearly defined edges (no soft or feathered edges); vary opacity for depth (import opaque layers, set transparency in Icon Composer); prefer vector (SVG/PDF) with text outlined; PNG for mesh gradients and raster art.
- Any imported background must be full-bleed and opaque. If using a gradient, make sure it responds well to system lighting.
- Layer groups let effects apply to several layers at once.

## Visual effects

- Do not bake in specular highlights, drop shadows between layers, bevels, blurs or glows. The system's are dynamic; custom ones are static and conflict. If you add any, use them intentionally and test in Icon Composer, a simulated device, or a real device.

## Design rules

- Simple: a core concept, minimal number of shapes, simple background (solid or gradient); you need not fill the whole canvas.
- Consider filled, overlapping shapes, ideally with transparency, for depth.
- No text unless essential to experience or brand (hurts accessibility and localization, too small, cluttered). A mnemonic like a first letter is acceptable; avoid words like "Watch", "Play", "New".
- Prefer illustrations to photos; no replicated UI components or screenshots; avoid extremely thin lines and sharp corners (lose crispness at small sizes).
- No replicas of Apple hardware.
- Keep design consistent and optically balanced across all platforms the app supports.

## Appearances: light, dark, clear, tinted

- People choose default, dark, clear or tinted Home Screen icons (iOS, iPadOS, macOS). You may design each variant; the system generates the ones you omit.
- Keep core visual features identical across appearances; do not swap elements per variant.
- Base the dark icon on the light one; dark is more subdued, clear and tinted more so. Use complementary colors, avoid excessively bright images; colored backgrounds give the best contrast in dark. Make sure each remains visible, legible and recognizable beside system icons and widgets.
- Alternate app icons (iOS/iPadOS) each need their own dark, clear and tinted variants.

## Interface icons (HIG Icons) vs app icons

Interface icons (glyphs) are separate from app icons: streamlined shapes in black plus clear, colorized by the system, or SF Symbols.

- Highly simplified, recognizable; consistent size, detail, stroke weight and perspective across the set; match weight of adjacent text.
- Add padding for optical (not just geometric) centering when needed.
- Provide a selected-state version only if necessary (the system handles it in toolbars, tab bars, buttons).
- Text only if essential, and localize it; provide a flipped version for right-to-left text suggestions.
- Custom icons as vector (PDF/SVG); PNG only for assets with shading/texture, which then need multiple scales. Alternatively make a custom SF Symbol.
- Provide an accessibility label for every icon; use inclusive imagery; no Apple hardware replicas.

## macOS document icons

- Optional: if absent, macOS composites your app icon and the file extension onto the folded-corner shape.
- Supply any combination of background fill, center image and text; system layers, positions, masks them. Must be readable down to 16x16 px; reduce detail at small sizes; keep important content out of the top-right corner (fold).
- Background fill sizes: 512, 256, 128, 32, 16 px at @1x and double at @2x (1024 down to 32). Center image is half the canvas size (sizes 256, 128, 32, 16 @1x/@2x).
- Keep a margin of about 10% of the canvas; content ideally about 80% (205x205 inside 256x256).
- Short descriptive term optional instead of the extension (system capitalizes it).
