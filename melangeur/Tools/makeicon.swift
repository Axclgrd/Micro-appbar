import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Générateur de l'icône du Mélangeur, style « Liquid Glass ».
//
// Même construction que le reste de la famille — squircle, verre teinté, liseré
// spéculaire — avec une teinte laiton, la seule encore libre : jaune doré, plus
// clair et plus franc que l'ambre brun d'Éveil, et la couleur des potards
// d'une vraie console.
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

/// Trois tirettes de console : une glissière, un curseur, à trois hauteurs.
///
/// À seize pixels, la glissière fine disparaît : ce sont les trois curseurs,
/// larges et pleins, qui portent la silhouette — trois pavés en escalier qu'on
/// lit encore comme « réglages ». Tout est rempli par enroulement, ce qui
/// unit glissières et curseurs sans percer leurs recouvrements.
func faders(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let colonnes: [(CGFloat, CGFloat)] = [(0.18, 0.66), (0.50, 0.30), (0.82, 0.54)]
    let rail = rect.width * 0.075
    let curseurL = rect.width * 0.27, curseurH = rect.height * 0.17
    for (x, hauteur) in colonnes {
        let cx = rect.minX + rect.width * x
        path.addRoundedRect(in: CGRect(x: cx - rail / 2, y: rect.minY, width: rail, height: rect.height),
                            cornerWidth: rail / 2, cornerHeight: rail / 2)
        let cy = rect.minY + rect.height * hauteur
        path.addRoundedRect(in: CGRect(x: cx - curseurL / 2, y: cy - curseurH / 2, width: curseurL, height: curseurH),
                            cornerWidth: curseurH * 0.35, cornerHeight: curseurH * 0.35)
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
    ctx.setFillColor(CGColor(red: 0.50, green: 0.36, blue: 0.04, alpha: 1))
    ctx.fillPath()

    // 2. Corps : bronze profond → laiton clair.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.00, 0.30, 0.20, 0.01, 1.0),
            (0.45, 0.82, 0.62, 0.08, 1.0),
            (1.00, 1.00, 0.90, 0.48, 1.0),
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
            (0.0, 0.16, 0.10, 0.01, 0.45),
            (0.35, 0.16, 0.10, 0.01, 0.0),
        ]),
        start: CGPoint(x: plate.midX, y: plate.minY),
        end: CGPoint(x: plate.midX, y: plate.midY),
        options: []
    )
    ctx.restoreGState()

    // 5. Le glyphe : les trois tirettes, en verre dépoli.
    let glyph = faders(in: CGRect(x: plate.minX + plate.width * 0.22, y: plate.minY + plate.height * 0.22,
                                  width: plate.width * 0.56, height: plate.height * 0.56))

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.008),
                  blur: canvas * 0.028,
                  color: CGColor(red: 0.22, green: 0.14, blue: 0.01, alpha: 0.55))
    ctx.addPath(glyph)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.94))
    // Remplissage par enroulement, pas en pair-impair : glissières et
    // curseurs se recouvrent, et le pair-impair y percerait des trous.
    ctx.fillPath()
    ctx.restoreGState()

    // Dégradé sur le glyphe : lumineux en haut, translucide en bas.
    ctx.saveGState()
    ctx.addPath(glyph)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.0, 1.00, 0.92, 0.62, 0.50),
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
                    : "build/Melangeur.iconset")
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
