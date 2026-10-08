import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Générateur de l'icône applicative, style « Liquid Glass ».
//
// Rendu par code plutôt qu'en image figée : l'icône se régénère à toutes les
// tailles, et les réglages ci-dessous restent modifiables.
//
// Compilation : swiftc -O Tools/makeicon.swift -o /tmp/makeicon

let canvas: CGFloat = 1024
// Les icônes macOS ne remplissent pas leur toile : le contenu est encarté pour
// laisser respirer l'ombre portée.
let inset: CGFloat = canvas * 0.09
let plate = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)

// MARK: - Formes

/// Squircle façon Apple : une superellipse, pas un rectangle à coins arrondis.
/// La différence est subtile mais c'est elle qui fait « natif ».
func squircle(in rect: CGRect, exponent: CGFloat = 5.0, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let cx = rect.midX, cy = rect.midY
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * CGFloat(sign(ct)) * pow(abs(ct), 2 / exponent)
        let y = cy + b * CGFloat(sign(st)) * pow(abs(st), 2 / exponent)
        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func sign(_ v: CGFloat) -> CGFloat { v < 0 ? -1 : 1 }

func polar(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
    CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
}

/// Pales du ventilateur.
///
/// Le piège : des pales symétriques donnent une fleur, pas une turbine. Ce qui
/// fait lire « ventilateur », c'est l'asymétrie — un bord d'attaque qui balaie
/// largement dans le sens de rotation, et un bord de fuite qui revient vers le
/// moyeu en creusant. L'œil y voit un mouvement.
func fanBlades(center: CGPoint, inner: CGFloat, outer: CGFloat, count: Int = 5) -> CGPath {
    let path = CGMutablePath()
    let step = 2 * CGFloat.pi / CGFloat(count)
    for i in 0..<count {
        let a = CGFloat(i) * step
        // Pied large, entièrement masqué par le moyeu : une racine réduite à un
        // point donnerait des pales pincées, avec des trous autour du centre.
        path.move(to: polar(center, inner, a - 0.30))

        // Bord d'attaque : quitte le moyeu presque radialement puis s'enroule.
        path.addCurve(
            to: polar(center, outer, a + 0.74),
            control1: polar(center, outer * 0.42, a - 0.02),
            control2: polar(center, outer * 0.86, a + 0.38)
        )
        // Extrémité arrondie, légèrement débordante : la pale a une épaisseur.
        path.addCurve(
            to: polar(center, outer * 0.82, a + 1.04),
            control1: polar(center, outer * 1.05, a + 0.90),
            control2: polar(center, outer * 0.97, a + 1.03)
        )
        // Bord de fuite : rentre vers le moyeu en creusant vers l'intérieur.
        path.addCurve(
            to: polar(center, inner, a + 0.50),
            control1: polar(center, outer * 0.52, a + 0.96),
            control2: polar(center, inner * 2.30, a + 0.70)
        )
        path.closeSubpath()
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

    // 1. Socle opaque, sans ombre portée.
    //
    //    Pas d'ombre bakée : macOS compose la sienne sous les icônes du Dock et
    //    du Finder. En cuire une dans l'image la double, et sur fond
    //    transparent son dégradé se quantifie en anneaux concentriques bien
    //    visibles — exactement le défaut qu'on cherche à éviter.
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(red: 0.12, green: 0.42, blue: 0.85, alpha: 1))
    ctx.fillPath()

    // 2. Corps : dégradé profond bleu nuit → cyan, l'assise « verre teinté ».
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.00, 0.10, 0.22, 0.55, 1.0),
            (0.45, 0.11, 0.45, 0.88, 1.0),
            (1.00, 0.30, 0.80, 0.95, 1.0),
        ]),
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )

    // 3. Réfraction : halo lumineux en haut à gauche, comme une épaisseur de
    //    verre qui capte la lumière ambiante.
    ctx.drawRadialGradient(
        makeGradient([
            (0.0, 1, 1, 1, 0.55),
            (1.0, 1, 1, 1, 0.0),
        ]),
        startCenter: CGPoint(x: plate.minX + plate.width * 0.26,
                             y: plate.maxY - plate.height * 0.18),
        startRadius: 0,
        endCenter: CGPoint(x: plate.minX + plate.width * 0.26,
                           y: plate.maxY - plate.height * 0.18),
        endRadius: plate.width * 0.72,
        options: []
    )

    // 4. Ombre interne en bas : donne de la profondeur au bloc de verre.
    ctx.drawLinearGradient(
        makeGradient([
            (0.0, 0.02, 0.06, 0.20, 0.42),
            (0.35, 0.02, 0.06, 0.20, 0.0),
        ]),
        start: CGPoint(x: plate.midX, y: plate.minY),
        end: CGPoint(x: plate.midX, y: plate.midY),
        options: []
    )
    ctx.restoreGState()

    // 5. Les pales, en verre dépoli clair.
    let outer = plate.width * 0.345
    let inner = plate.width * 0.072
    let blades = fanBlades(center: center, inner: inner, outer: outer)

    ctx.saveGState()
    // Ombre projetée des pales sur le fond : c'est ce qui les décolle.
    ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.008),
                  blur: canvas * 0.028,
                  color: CGColor(red: 0.02, green: 0.10, blue: 0.30, alpha: 0.55))
    ctx.addPath(blades)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.93))
    ctx.fillPath()
    ctx.restoreGState()

    // Dégradé sur les pales : plus lumineuses en haut, translucides en bas.
    ctx.saveGState()
    ctx.addPath(blades)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.0, 0.62, 0.85, 1.00, 0.55),
            (0.5, 1.00, 1.00, 1.00, 0.00),
            (1.0, 1.00, 1.00, 1.00, 0.38),
        ]),
        start: CGPoint(x: center.x, y: center.y - outer),
        end: CGPoint(x: center.x, y: center.y + outer),
        options: []
    )
    ctx.restoreGState()

    // 6. Moyeu central : petit disque de verre, avec sa propre lumière.
    let hubRect = CGRect(x: center.x - inner * 1.34, y: center.y - inner * 1.34,
                         width: inner * 2.68, height: inner * 2.68)
    ctx.saveGState()
    ctx.addEllipse(in: hubRect)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.0, 0.16, 0.34, 0.70, 1.0),
            (1.0, 0.55, 0.88, 1.00, 1.0),
        ]),
        start: CGPoint(x: hubRect.minX, y: hubRect.minY),
        end: CGPoint(x: hubRect.maxX, y: hubRect.maxY),
        options: []
    )
    ctx.restoreGState()

    // 7. Liseré supérieur : le reflet spéculaire sur l'arête du verre. C'est
    //    le détail qui vend la matière — sans lui l'icône paraît plate.
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
                    : "build/FanControl.iconset")
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

let master = renderIcon()
// Jeu de tailles attendu par `iconutil`.
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
// Aperçu pleine résolution, pratique pour juger le rendu.
write(master, size: 1024, to: outputDir.deletingLastPathComponent().appendingPathComponent("icon-preview.png"))
print("icônes écrites dans \(outputDir.path)")
