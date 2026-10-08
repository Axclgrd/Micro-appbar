import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Générateur de l'icône de Bande, style « Liquid Glass ».
//
// Même construction que celle de fancontrole, d'Éjecter et de Purge — squircle,
// verre teinté, liseré spéculaire — avec sa teinte turquoise et son glyphe :
// cinq barres d'égaliseur, la forme la plus lisible pour dire « son ».
//
// Compilation : swiftc -O Tools/makeicon.swift -o build/makeicon

let canvas: CGFloat = 1024
let inset: CGFloat = canvas * 0.09
let plate = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)

// MARK: - Formes

/// Squircle façon Apple : une superellipse, pas un rectangle à coins arrondis.
func squircle(in rect: CGRect, exponent: CGFloat = 5.0, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * sign(ct) * pow(abs(ct), 2 / exponent)
        let y = cy + b * sign(st) * pow(abs(st), 2 / exponent)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func sign(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : 1 }

/// L'égaliseur : cinq barres à bouts ronds, hauteurs asymétriques.
///
/// Le piège à 16 px, c'est le nombre de barres : à sept, elles se touchent et
/// l'ensemble devient un pavé gris. Cinq laissent un vide franc entre chaque,
/// et les hauteurs inégales sont ce qui distingue un son d'un code-barres.
func equalizer(center: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    let ratios: [CGFloat] = [0.42, 0.78, 1.00, 0.62, 0.32]
    let slot = width / CGFloat(ratios.count)
    let bar = slot * 0.52          // le reste est l'air entre les barres
    let path = CGMutablePath()
    for (i, ratio) in ratios.enumerated() {
        let x = center.x - width / 2 + slot * (CGFloat(i) + 0.5)
        let h = max(height * ratio, bar)
        let rect = CGRect(x: x - bar / 2, y: center.y - h / 2, width: bar, height: h)
        path.addRoundedRect(in: rect, cornerWidth: bar / 2, cornerHeight: bar / 2)
    }
    return path
}

// MARK: - Rendu

func makeGradient(_ stops: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)]) -> CGGradient {
    let space = CGColorSpaceCreateDeviceRGB()
    var comps: [CGFloat] = []
    var locs: [CGFloat] = []
    for (loc, r, g, b, a) in stops {
        locs.append(loc)
        comps.append(contentsOf: [r, g, b, a])
    }
    return CGGradient(colorSpace: space, colorComponents: comps, locations: locs, count: locs.count)!
}

func renderIcon() -> CGImage {
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let shape = squircle(in: plate)
    let center = CGPoint(x: plate.midX, y: plate.midY)

    // 1. Socle opaque, sans ombre portée : macOS compose la sienne.
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(red: 0.04, green: 0.32, blue: 0.36, alpha: 1))
    ctx.fillPath()

    // 2. Corps : teal profond → turquoise clair. Quatrième teinte de la
    //    famille, distincte du bleu thermique, du vert d'éjection et du violet.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.00, 0.02, 0.16, 0.24, 1.0),
            (0.45, 0.05, 0.49, 0.55, 1.0),
            (1.00, 0.48, 0.94, 0.90, 1.0),
        ]),
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )

    // 3. Réfraction : le halo qui donne l'épaisseur de verre.
    let glare = CGPoint(x: plate.minX + plate.width * 0.26, y: plate.maxY - plate.height * 0.18)
    ctx.drawRadialGradient(
        makeGradient([(0.0, 1, 1, 1, 0.55), (1.0, 1, 1, 1, 0.0)]),
        startCenter: glare, startRadius: 0,
        endCenter: glare, endRadius: plate.width * 0.72,
        options: []
    )

    // 4. Ombre interne basse.
    ctx.drawLinearGradient(
        makeGradient([
            (0.0, 0.01, 0.08, 0.12, 0.45),
            (0.35, 0.01, 0.08, 0.12, 0.0),
        ]),
        start: CGPoint(x: plate.midX, y: plate.minY),
        end: CGPoint(x: plate.midX, y: plate.midY),
        options: []
    )
    ctx.restoreGState()

    // 5. Le glyphe, en verre dépoli.
    let glyph = equalizer(center: center,
                          width: plate.width * 0.54,
                          height: plate.height * 0.52)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.008),
                  blur: canvas * 0.028,
                  color: CGColor(red: 0.00, green: 0.10, blue: 0.14, alpha: 0.55))
    ctx.addPath(glyph)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.94))
    ctx.fillPath()
    ctx.restoreGState()

    // Dégradé sur le glyphe : lumineux en haut, translucide en bas.
    ctx.saveGState()
    ctx.addPath(glyph)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.0, 0.62, 1.00, 0.98, 0.50),
            (0.5, 1.00, 1.00, 1.00, 0.00),
            (1.0, 1.00, 1.00, 1.00, 0.32),
        ]),
        start: CGPoint(x: center.x, y: plate.minY),
        end: CGPoint(x: center.x, y: plate.maxY),
        options: []
    )
    ctx.restoreGState()

    // 6. Liseré supérieur : le reflet sur l'arête. Sans lui, l'icône est plate.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.addPath(shape)
    ctx.setLineWidth(canvas * 0.007)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.00, 1, 1, 1, 0.95),
            (0.42, 1, 1, 1, 0.18),
            (1.00, 1, 1, 1, 0.06),
        ]),
        start: CGPoint(x: plate.midX, y: plate.maxY),
        end: CGPoint(x: plate.midX, y: plate.minY),
        options: []
    )
    ctx.restoreGState()

    return ctx.makeImage()!
}

// MARK: - Écriture

func write(_ image: CGImage, size: Int, to url: URL) {
    let space = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size,
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    let scaled = ctx.makeImage()!
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("destination PNG impossible : \(url.path)")
    }
    CGImageDestinationAddImage(dest, scaled, nil)
    CGImageDestinationFinalize(dest)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
                    ? CommandLine.arguments[1]
                    : "build/Bande.iconset")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let master = renderIcon()
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),     ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),     ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),  ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),  ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),  ("icon_512x512@2x.png", 1024),
]
for (name, size) in variants {
    write(master, size: size, to: outputDir.appendingPathComponent(name))
}
write(master, size: 1024, to: outputDir.deletingLastPathComponent().appendingPathComponent("icon-preview.png"))
print("icônes écrites dans \(outputDir.path)")
