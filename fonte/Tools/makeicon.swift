import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Générateur de l'icône de Fonte, style « Liquid Glass ».
//
// Même construction que le reste de la famille — squircle, verre teinté, liseré
// spéculaire — avec sa teinte graphite et son glyphe : le cadre de visée de
// Grab, et dedans un « Ag » en Didot, la paire de lettres que les typographes
// regardent d'abord pour reconnaître une famille.
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

/// Les quatre équerres d'un cadre de visée, comme sur l'icône de Grab : les
/// deux outils partent du même geste, sélectionner une zone de l'écran.
func viewfinder(in rect: CGRect, arm: CGFloat, thickness: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let corners: [(CGPoint, CGFloat, CGFloat)] = [
        (CGPoint(x: rect.minX, y: rect.maxY),  1, -1),   // haut gauche
        (CGPoint(x: rect.maxX, y: rect.maxY), -1, -1),   // haut droit
        (CGPoint(x: rect.minX, y: rect.minY),  1,  1),   // bas gauche
        (CGPoint(x: rect.maxX, y: rect.minY), -1,  1),   // bas droit
    ]
    for (corner, dx, dy) in corners {
        let bracket = CGMutablePath()
        bracket.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        bracket.addLine(to: corner)
        bracket.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        path.addPath(bracket.copy(strokingWithWidth: thickness, lineCap: .round,
                                  lineJoin: .round, miterLimit: 10))
    }
    return path
}

/// Des lettres réduites à leurs contours, centrées sur un point.
///
/// Didot Bold : son contraste extrême — pleins épais, déliés filiformes — se
/// lit encore à 32 px, là où une linéale ne dirait pas « typographie ». Elle
/// est livrée avec macOS ; à défaut, CoreText retombe sur une police système
/// et l'icône reste correcte.
func letters(_ string: String, font name: String, size: CGFloat, center: CGPoint) -> CGPath {
    let font = CTFontCreateWithName(name as CFString, size, nil)
    let attributed = NSAttributedString(string: string,
                                        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
    let line = CTLineCreateWithAttributedString(attributed)
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        let attributes = CTRunGetAttributes(run) as NSDictionary
        let runFont = attributes[kCTFontAttributeName as String] as! CTFont
        for i in 0..<count {
            guard let glyph = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
            path.addPath(glyph, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
        }
    }
    let box = path.boundingBoxOfPath
    var move = CGAffineTransform(translationX: center.x - box.midX, y: center.y - box.midY)
    return path.copy(using: &move) ?? path
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
    ctx.setFillColor(CGColor(red: 0.22, green: 0.23, blue: 0.27, alpha: 1))
    ctx.fillPath()

    // 2. Corps : encre profonde → graphite clair. La seule teinte neutre de
    //    la famille — celle du plomb des caractères mobiles — et la plus
    //    éloignée des couleurs vives des autres outils.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.00, 0.05, 0.05, 0.08, 1.0),
            (0.50, 0.20, 0.21, 0.26, 1.0),
            (1.00, 0.52, 0.55, 0.62, 1.0),
        ]),
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )

    // 3. Réfraction : le halo qui donne l'épaisseur de verre.
    let glare = CGPoint(x: plate.minX + plate.width * 0.26, y: plate.maxY - plate.height * 0.18)
    ctx.drawRadialGradient(
        makeGradient([(0.0, 1, 1, 1, 0.42), (1.0, 1, 1, 1, 0.0)]),
        startCenter: glare, startRadius: 0,
        endCenter: glare, endRadius: plate.width * 0.72,
        options: []
    )

    // 4. Ombre interne basse.
    ctx.drawLinearGradient(
        makeGradient([
            (0.0, 0.02, 0.02, 0.04, 0.50),
            (0.35, 0.02, 0.02, 0.04, 0.0),
        ]),
        start: CGPoint(x: plate.midX, y: plate.minY),
        end: CGPoint(x: plate.midX, y: plate.midY),
        options: []
    )
    ctx.restoreGState()

    // 5. Le glyphe : cadre de visée et « Ag », en verre dépoli.
    let frame = plate.insetBy(dx: plate.width * 0.17, dy: plate.height * 0.19)
    let glyph = CGMutablePath()
    glyph.addPath(viewfinder(in: frame,
                             arm: plate.width * 0.10,
                             thickness: plate.width * 0.050))
    glyph.addPath(letters("Ag", font: "Didot-Bold", size: plate.height * 0.40,
                          center: CGPoint(x: center.x, y: center.y + plate.height * 0.005)))

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -canvas * 0.008),
                  blur: canvas * 0.028,
                  color: CGColor(red: 0.0, green: 0.0, blue: 0.03, alpha: 0.6))
    ctx.addPath(glyph)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.fillPath()
    ctx.restoreGState()

    // Dégradé sur le glyphe : un reflet chaud en bas, comme du papier sous
    // la lampe, translucide au milieu, lumineux en haut.
    ctx.saveGState()
    ctx.addPath(glyph)
    ctx.clip()
    ctx.drawLinearGradient(
        makeGradient([
            (0.0, 1.00, 0.90, 0.76, 0.45),
            (0.5, 1.00, 1.00, 1.00, 0.00),
            (1.0, 1.00, 1.00, 1.00, 0.30),
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
                    : "build/Fonte.iconset")
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
