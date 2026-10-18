import CoreGraphics
import CoreText
import Foundation

/// Le tri visuel, fait sur le Mac : quelles polices se superposent le mieux à
/// la ligne capturée ?
///
/// Claude propose de mémoire, et sa mémoire a des trous : Clash Display ou
/// General Sans ne lui venaient jamais, même listées sous ses yeux. Or quand
/// on compose la ligne capturée à la même hauteur dans la bonne police, elle
/// se superpose presque exactement — même largeur, mêmes formes. Cette
/// mesure, on peut la faire seul, sur des centaines de polices, en une
/// seconde. Les meilleures rejoignent les propositions de Claude, qui reste
/// seul juge.
enum Screening {

    /// Les polices du bassin qui se superposent le mieux à la ligne, de la
    /// plus proche à la moins proche.
    static func closest(to zoom: Reading.Zoom, among faces: [Library.Face], count: Int) -> [Library.Face] {
        guard let target = Mask(capture: zoom) else { return [] }
        let scores = Scores(count: faces.count)
        DispatchQueue.concurrentPerform(iterations: faces.count) { index in
            let face = faces[index]
            guard covers(face.font, zoom.text),
                  let mask = Mask(text: zoom.text, font: face.font, inkHeight: target.inkHeight)
            else { return }
            scores.set(index, distance(target, mask))
        }
        // La meilleure graisse de chaque famille, puis les meilleures familles.
        var best: [String: (Library.Face, Double)] = [:]
        for (index, score) in scores.values.enumerated() {
            guard let score else { continue }
            let family = Library.key(faces[index].family)
            if best[family].map({ score < $0.1 }) ?? true { best[family] = (faces[index], score) }
        }
        return best.values
            .sorted { $0.1 < $1.1 }
            .prefix(count)
            .map(\.0)
    }

    /// Ce que mesure la superposition d'une police sur la ligne capturée.
    struct Fit: Sendable {
        /// Largeur composée sur largeur capturée, à hauteur égale : 1 si
        /// elles se superposent.
        let width: Double
        /// Part d'encre commune, de 0 à 1, une fois les largeurs égalisées.
        let overlap: Double
    }

    static func fit(of face: Library.Face, on zoom: Reading.Zoom) -> Fit? {
        guard covers(face.font, zoom.text),
              let target = Mask(capture: zoom),
              let mask = Mask(text: zoom.text, font: face.font, inkHeight: target.inkHeight)
        else { return nil }
        return Fit(width: Double(mask.width) / Double(target.width), overlap: target.overlap(mask))
    }

    /// Une police qui n'a pas toutes les lettres serait complétée par une
    /// autre à l'affichage : sa ressemblance serait celle de la remplaçante.
    static func covers(_ font: CTFont, _ text: String) -> Bool {
        let units = Array(text.filter { !$0.isWhitespace }.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: units.count)
        return CTFontGetGlyphsForCharacters(font, units, &glyphs, units.count)
    }

    /// Plus c'est petit, plus c'est proche. L'écart de largeur pèse double :
    /// à hauteur égale, c'est le signe le plus sûr d'une autre police, et le
    /// moins brouillé par le flou.
    private static func distance(_ a: Mask, _ b: Mask) -> Double {
        let width = abs(log(Double(b.width) / Double(a.width)))
        return width * 2 + (1 - a.overlap(b))
    }

    // MARK: Masques

    /// L'encre d'une ligne, recadrée et ramenée à une hauteur fixe.
    struct Mask {
        static let height = 40

        let width: Int
        let pixels: [Float]
        /// La hauteur de l'encre avant réduction, pour composer à l'identique.
        let inkHeight: CGFloat

        init?(capture zoom: Reading.Zoom) {
            guard let ink = Reading.Ink(zoom.image, core: zoom.core), ink.rect.height > 4 else { return nil }
            self.init(ink: ink, inkHeight: ink.rect.height)
        }

        init?(text: String, font: CTFont, inkHeight: CGFloat) {
            let probe = Self.line(text, font: font, size: 100)
            let bounds = CTLineGetBoundsWithOptions(probe, .useGlyphPathBounds)
            guard bounds.height > 0 else { return nil }
            let size = 100 * inkHeight / bounds.height
            let line = Self.line(text, font: font, size: size)
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            // Une marge large : l'encre ne doit pas toucher les rangées du
            // bord, que la mesure efface comme une ligne voisine.
            let margin: CGFloat = 12
            let width = Int(ceil(ink.width + margin * 2)), height = Int(ceil(ink.height + margin * 2))
            guard width < 6000,
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return nil }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.textPosition = CGPoint(x: margin - ink.minX, y: margin - ink.minY)
            CTLineDraw(line, context)
            guard let image = context.makeImage(), let ink = Reading.Ink(image) else { return nil }
            self.init(ink: ink, inkHeight: inkHeight)
        }

        /// Réduction par moyenne : chaque pixel du masque vaut la part
        /// d'encre de la zone qu'il couvre.
        private init(ink: Reading.Ink, inkHeight: CGFloat) {
            let rect = ink.rect
            let scale = CGFloat(Self.height) / rect.height
            let width = max(1, Int((rect.width * scale).rounded()))
            var pixels = [Float](repeating: 0, count: width * Self.height)
            for y in 0..<Self.height {
                let y0 = Int(rect.minY + CGFloat(y) / scale), y1 = max(y0 + 1, Int(rect.minY + CGFloat(y + 1) / scale))
                for x in 0..<width {
                    let x0 = Int(rect.minX + CGFloat(x) / scale), x1 = max(x0 + 1, Int(rect.minX + CGFloat(x + 1) / scale))
                    var inked = 0, total = 0
                    for yy in y0..<min(y1, ink.height) {
                        for xx in x0..<min(x1, ink.width) {
                            total += 1
                            if ink.isInk(xx, yy) { inked += 1 }
                        }
                    }
                    pixels[y * width + x] = total > 0 ? Float(inked) / Float(total) : 0
                }
            }
            self.width = width
            self.pixels = pixels
            self.inkHeight = inkHeight
        }

        /// La part d'encre commune, une fois l'autre masque étiré à la même
        /// largeur : la forme des lettres, indépendamment de leur chasse.
        func overlap(_ other: Mask) -> Double {
            var common: Float = 0, either: Float = 0
            for y in 0..<Self.height {
                for x in 0..<width {
                    let ox = min(other.width - 1, x * other.width / width)
                    let a = pixels[y * width + x], b = other.pixels[y * other.width + ox]
                    common += min(a, b)
                    either += max(a, b)
                }
            }
            return either > 0 ? Double(common / either) : 0
        }

        private static func line(_ text: String, font: CTFont, size: CGFloat) -> CTLine {
            let sized = CTFontCreateCopyWithAttributes(font, size, nil, nil)
            return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): sized,
            ]))
        }
    }

    private final class Scores: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var values: [Double?]
        init(count: Int) { values = Array(repeating: nil, count: count) }
        func set(_ index: Int, _ value: Double) {
            lock.lock(); values[index] = value; lock.unlock()
        }
    }
}
