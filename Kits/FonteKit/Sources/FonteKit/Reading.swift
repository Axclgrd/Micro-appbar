import AppKit
import CoreImage
import CoreText
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Ce que le Mac voit seul, avant Claude : où est le texte, et à quoi il
/// ressemble de près.
///
/// Une police se reconnaît à des détails d'un pixel — la coupe d'un « t », la
/// queue d'un « g ». Dans une photo de packaging, ces lettres font quinze
/// pixels de haut, penchées sur la face d'une boîte. Vision trouve chaque
/// ligne et son contour réel ; on la redresse, on l'agrandit, et Claude
/// reçoit les lettres à plat, à une taille où elles se lisent.
enum Reading {

    struct Line: Sendable {
        let text: String
        /// Les quatre coins dans l'image, en pixels, origine en bas à gauche
        /// (repère de Core Image) : haut gauche, haut droit, bas droit, bas gauche.
        let corners: [CGPoint]
        let height: CGFloat
    }

    // MARK: Lecture

    static func lines(in image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Pas de correction : un nom de marque n'est pas une faute.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR", "en-US"]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }

        let size = CGSize(width: image.width, height: image.height)
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespaces)
            guard text.count >= 2 else { return nil }
            let corners = [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                .map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            let height = (hypot(corners[0].x - corners[3].x, corners[0].y - corners[3].y)
                + hypot(corners[1].x - corners[2].x, corners[1].y - corners[2].y)) / 2
            return Line(text: text, corners: corners, height: height)
        }
    }

    // MARK: Agrandissements

    /// Une ligne de la capture, redressée et agrandie.
    struct Zoom: @unchecked Sendable {
        let text: String
        let image: CGImage
        let png: Data
        /// La ligne occupe déjà presque toute la capture : l'envoyer en plus
        /// à Claude répéterait l'image d'origine. Elle sert quand même de
        /// référence pour les comparaisons.
        let redundant: Bool
        /// Le cadre du texte trouvé par Vision, dans l'image agrandie (origine
        /// en haut à gauche) : autour, c'est le fond.
        let core: CGRect
    }

    /// Les lignes les plus grandes, redressées et agrandies.
    ///
    /// Trois au plus : au-delà, on répète les mêmes lettres.
    static func zooms(of image: CGImage, lines: [Line], limit: Int = 3) -> [Zoom] {
        let picked = pick(lines, limit: limit)
        let area = CGFloat(image.width * image.height)
        // Le cadre élargi peut déborder de la capture : on prolonge ses bords
        // plutôt que de laisser un vide, que la mesure de l'encre prendrait
        // pour du texte.
        let source = CIImage(cgImage: image).clampedToExtent()
        let context = CIContext()

        return picked.compactMap { line in
            let quad = expanded(line)
            let width = hypot(quad[1].x - quad[0].x, quad[1].y - quad[0].y)
            let height = hypot(quad[0].x - quad[3].x, quad[0].y - quad[3].y)
            let scale = min(4, max(1, target / line.height))
            let redundant = scale < 1.3 && width * height > area * 0.55 && !isTilted(line)

            let straight = source.applyingFilter("CIPerspectiveCorrection", parameters: [
                "inputTopLeft": CIVector(cgPoint: quad[0]),
                "inputTopRight": CIVector(cgPoint: quad[1]),
                "inputBottomRight": CIVector(cgPoint: quad[2]),
                "inputBottomLeft": CIVector(cgPoint: quad[3]),
            ])
            let large = straight.applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1,
            ])
            // Les bords du redressement sont à demi transparents : on les rogne.
            guard let raw = context.createCGImage(large, from: large.extent.insetBy(dx: 2, dy: 2).integral)
            else { return nil }
            // Le cadre de Vision, sans les marges ajoutées par `expanded`.
            let side = line.height * 0.4 * scale, edge = line.height * 0.35 * scale
            let core = CGRect(x: side - 2, y: edge - 2,
                              width: max(1, width * scale - side * 2), height: max(1, height * scale - edge * 2))
            let cg = level(raw, core: core, context: context)
            guard let data = png(cg) else { return nil }
            return Zoom(text: line.text, image: cg, png: data, redundant: redundant, core: core)
        }
    }

    /// Remet la ligne à l'horizontale.
    ///
    /// Le contour de Vision est un rectangle tourné : il suit la rotation
    /// d'une ligne, pas la perspective d'un objet photographié. Il reste une
    /// pente, que l'on lit sur le pied des lettres — à gauche et à droite,
    /// la médiane des bas de colonnes, où les jambages sont minoritaires.
    private static func level(_ image: CGImage, core: CGRect, context: CIContext) -> CGImage {
        guard let ink = Ink(image, core: core), ink.rect.width > ink.rect.height * 2 else { return image }
        let rect = ink.rect
        func baseline(_ from: Int, _ to: Int) -> Double? {
            var bottoms: [Int] = []
            for x in from..<to {
                var bottom = -1
                for y in Int(rect.minY)..<Int(rect.maxY) where ink.isInk(x, y) {
                    bottom = y
                }
                if bottom >= 0 { bottoms.append(bottom) }
            }
            guard bottoms.count >= 3 else { return nil }
            return Double(bottoms.sorted()[bottoms.count / 2])
        }
        let third = Int(rect.width / 3)
        guard third > 4,
              let left = baseline(Int(rect.minX), Int(rect.minX) + third),
              let right = baseline(Int(rect.maxX) - third, Int(rect.maxX))
        else { return image }
        // Les centres des deux tiers sont à deux tiers de largeur l'un de
        // l'autre. Origine en haut : une pente positive descend vers la droite.
        let angle = atan2(right - left, Double(rect.width) * 2 / 3)
        guard abs(angle) > 0.008, abs(angle) < 0.26 else { return image }

        let source = CIImage(cgImage: image)
        let center = CGPoint(x: source.extent.midX, y: source.extent.midY)
        // Core Image a l'origine en bas : la même pente se corrige en
        // tournant dans le sens direct.
        let turned = source.clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(angle)))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
            .cropped(to: source.extent)
        // Une ligne remise à plat est moins haute : sinon, la pente était mal
        // lue (un jambage, une ligne voisine), et on garde l'image telle quelle.
        guard let result = context.createCGImage(turned, from: source.extent),
              let after = Ink(result, core: core), after.rect.height < rect.height * 0.97
        else { return image }
        return result
    }

    static func grayPixels(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let raw = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        return Array(UnsafeBufferPointer(start: raw, count: width * height))
    }

    // MARK: Comparaisons

    /// Chaque ligne capturée, et juste dessous la même ligne composée dans
    /// la police : à la même hauteur de lettres, alignées à gauche.
    ///
    /// C'est la comparaison d'un typographe. Deux images séparées, à deux
    /// échelles, se comparent mal — Claude y confondait Bebas Neue et Oswald.
    /// À hauteur égale et l'une sous l'autre, une lettre plus large, un « R »
    /// à jambe droite ou un « J » qui descend sautent aux yeux.
    static func comparison(_ zooms: [Zoom], font: CTFont) -> Data? {
        let rows = zooms.prefix(2).compactMap { zoom -> (Zoom, CGRect, CTLine, CGRect)? in
            guard let ink = Ink(zoom.image, core: zoom.core)?.rect, ink.height > 4 else { return nil }
            // Une première composition pour mesurer, la seconde à la taille
            // qui donne la même hauteur d'encre que la capture.
            let probe = line(zoom.text, font: font, size: 100)
            let probeInk = CTLineGetBoundsWithOptions(probe, .useGlyphPathBounds)
            guard probeInk.height > 0 else { return nil }
            let size = 100 * ink.height / probeInk.height
            let final = line(zoom.text, font: font, size: size)
            return (zoom, ink, final, CTLineGetBoundsWithOptions(final, .useGlyphPathBounds))
        }
        guard !rows.isEmpty else { return nil }

        let gap: CGFloat = 14, divider: CGFloat = 2
        let heights = rows.map { CGFloat($0.0.image.height) * 2 + gap * 2 }
        let width = Int(rows.map { max(CGFloat($0.0.image.width), $0.1.minX + $0.3.width + 24) }.max() ?? 0)
        let total = Int(heights.reduce(0, +) + divider * CGFloat(rows.count - 1))
        guard width > 0, total > 0, width < 8000,
              let context = CGContext(data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: total))

        // De haut en bas : Core Graphics compte depuis le bas.
        var top = CGFloat(total)
        for (index, row) in rows.enumerated() {
            let (zoom, ink, rendered, bounds) = row
            let zoomHeight = CGFloat(zoom.image.height)
            context.draw(zoom.image, in: CGRect(x: 0, y: top - zoomHeight, width: CGFloat(zoom.image.width), height: zoomHeight))
            // Même ligne de base relative : le bas de l'encre composée tombe
            // à la même hauteur, dans sa bande, que le bas de l'encre capturée.
            let bandTop = top - zoomHeight - gap
            let inkBottom = bandTop - ink.maxY
            context.textPosition = CGPoint(x: ink.minX - bounds.minX, y: inkBottom - bounds.minY)
            CTLineDraw(rendered, context)
            top -= heights[index]
            if index < rows.count - 1 {
                context.setFillColor(CGColor(gray: 0.75, alpha: 1))
                context.fill(CGRect(x: 0, y: top - divider, width: CGFloat(width), height: divider))
                top -= divider
            }
        }
        return context.makeImage().flatMap(png)
    }

    private static func line(_ text: String, font: CTFont, size: CGFloat) -> CTLine {
        let sized = CTFontCreateCopyWithAttributes(font, size, nil, nil)
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): sized,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]))
    }

    /// L'encre d'une ligne capturée : quels pixels sont des lettres.
    struct Ink {
        let width: Int
        let height: Int
        /// Vrai pour un pixel de lettre, rangées de haut en bas.
        let mask: [Bool]
        /// Le rectangle des lettres, origine en haut à gauche.
        let rect: CGRect

        func isInk(_ x: Int, _ y: Int) -> Bool { mask[y * width + x] }

        /// Quatre règles, chacune née d'un échec :
        ///
        /// - Le fond se lit juste autour du texte, sur un anneau autour du
        ///   cadre de Vision. Ni toute l'image — une capitale très grasse
        ///   couvre plus de pixels que son fond — ni les marges : un cadrage
        ///   qui déborde d'un bandeau coloré a des marges blanches, et texte
        ///   et fond s'inversaient.
        /// - Le seuil suit le contraste : la moitié de l'écart le plus fort.
        ///   Un seuil fixe perdait les traits fins d'une Light photographiée.
        /// - Ce qui touche le haut ou le bas est écarté : l'extérieur d'un
        ///   bandeau, ou la ligne voisine qu'un cadrage serré a coupée. Pas
        ///   les côtés : des capitales grasses se touchent, et un mot entier
        ///   relié au bord gauche disparaissait.
        /// - Seule la bande de la ligne est gardée : les points des « i » de la
        ///   ligne suivante, qui ne touchent aucun bord, faussaient la hauteur.
        ///
        /// Sans `core` (un rendu, noir sur blanc), le fond se lit sur les
        /// rangées du haut et du bas.
        init?(_ image: CGImage, core: CGRect? = nil) {
            let width = image.width, height = image.height
            guard width > 8, height > 8, let gray = Reading.grayPixels(image) else { return nil }
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)

            var histogram = [Int](repeating: 0, count: 256)
            if let core, core.height > 2 {
                let ring = core.insetBy(dx: -core.height * 0.15, dy: -core.height * 0.15).intersection(bounds)
                for y in Int(ring.minY)..<Int(ring.maxY) {
                    for x in Int(ring.minX)..<Int(ring.maxX)
                    where !core.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) {
                        histogram[Int(gray[y * width + x])] += 1
                    }
                }
            }
            if histogram.reduce(0, +) < 20 {
                let band = max(2, height / 12)
                for y in Array(0..<band) + Array((height - band)..<height) {
                    for x in 0..<width { histogram[Int(gray[y * width + x])] += 1 }
                }
            }
            // Une fenêtre de neuf niveaux : le bruit et la compression
            // éparpillent le fond sur quelques valeurs voisines.
            let smoothed = (0..<256).map { level in
                (max(0, level - 4)...min(255, level + 4)).reduce(0) { $0 + histogram[$1] }
            }
            let background = smoothed.indices.max { smoothed[$0] < smoothed[$1] } ?? 255

            var differences = [Int](repeating: 0, count: 256)
            for value in gray { differences[abs(Int(value) - background)] += 1 }
            var seen = 0, strongest = 255
            for level in stride(from: 255, through: 0, by: -1) {
                seen += differences[level]
                if seen >= max(1, gray.count / 100) { strongest = level; break }
            }
            let threshold = max(18, strongest / 2)

            let raw = gray.map { abs(Int($0) - background) > threshold }
            var mask = raw

            // Ce qui touche le haut ou le bas, de proche en proche. Deux
            // rangées de chaque côté : la dernière est parfois adoucie.
            var stack: [Int] = []
            for x in 0..<width { stack += [x, width + x, (height - 1) * width + x, (height - 2) * width + x] }
            while let index = stack.popLast() {
                guard mask[index] else { continue }
                mask[index] = false
                let x = index % width, y = index / width
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        if nx >= 0, nx < width, ny >= 0, ny < height, mask[ny * width + nx] { stack.append(ny * width + nx) }
                    }
                }
            }

            // Si l'effacement vide le cadre du texte, c'est le texte lui-même
            // qui touchait le bord : on garde tout. Hors du cadre, perdre
            // beaucoup est normal — l'extérieur d'un bandeau est souvent plus
            // grand que les lettres.
            let area = (core ?? bounds).intersection(bounds)
            var kept = 0, found = 0
            for y in Int(area.minY)..<Int(area.maxY) {
                for x in Int(area.minX)..<Int(area.maxX) {
                    if raw[y * width + x] { found += 1 }
                    if mask[y * width + x] { kept += 1 }
                }
            }
            if kept * 10 < found * 3 { mask = raw }

            // La bande de la ligne : depuis la rangée encrée la plus proche du
            // milieu du cadre, tant que les blancs restent courts — l'accent
            // d'un « É » est gardé, un point de la ligne suivante ne l'est pas.
            var rows = [Int](repeating: 0, count: height)
            for y in 0..<height { for x in 0..<width where mask[y * width + x] { rows[y] += 1 } }
            let middle = Int(core?.midY ?? CGFloat(height) / 2)
            let allowed = max(3, Int((core?.height ?? CGFloat(height) / 1.7) * 0.15))
            func cost(_ y: Int) -> Int { abs(y - middle) + (rows[y] >= 2 ? 0 : height) }
            if let center = (0..<height).min(by: { cost($0) < cost($1) }), rows[center] >= 2 {
                func extend(_ step: Int) -> Int {
                    var edge = center, y = center, blank = 0
                    while y + step >= 0, y + step < height {
                        y += step
                        if rows[y] >= 2 { edge = y; blank = 0 } else { blank += 1; if blank > allowed { break } }
                    }
                    return edge
                }
                let top = extend(-1), bottom = extend(1)
                for y in 0..<height where y < top || y > bottom {
                    for x in 0..<width { mask[y * width + x] = false }
                }
            }

            guard let rect = Self.bounds(mask, width: width, height: height) else { return nil }
            self.width = width
            self.height = height
            self.mask = mask
            self.rect = rect
        }

        /// Une rangée ou une colonne compte si deux pixels au moins sont de
        /// l'encre : un point isolé est du bruit.
        private static func bounds(_ mask: [Bool], width: Int, height: Int) -> CGRect? {
            var rows = [Int](repeating: 0, count: height), columns = [Int](repeating: 0, count: width)
            for y in 0..<height {
                for x in 0..<width where mask[y * width + x] { rows[y] += 1; columns[x] += 1 }
            }
            guard let minY = rows.firstIndex(where: { $0 >= 2 }), let maxY = rows.lastIndex(where: { $0 >= 2 }),
                  let minX = columns.firstIndex(where: { $0 >= 2 }), let maxX = columns.lastIndex(where: { $0 >= 2 }),
                  maxX > minX, maxY > minY
            else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }
    }

    /// La hauteur visée pour une ligne agrandie : assez pour voir la coupe
    /// d'un empattement, pas tant que l'image pèse pour rien.
    private static let target: CGFloat = 150

    /// Les lignes qui montrent le plus de lettres différentes, en grand.
    ///
    /// Un packaging répète le même mot sur chaque face : trois agrandissements
    /// de « HEMP FARM » n'apprennent rien de plus qu'un seul. Chaque ligne
    /// choisie ne compte donc que pour les lettres qu'elle ajoute, pesées par
    /// sa taille — le texte principal est le plus grand.
    private static func pick(_ lines: [Line], limit: Int) -> [Line] {
        func letters(_ line: Line) -> Set<Character> {
            Set(line.text.uppercased().filter { $0.isLetter || $0.isNumber })
        }
        var covered = Set<Character>()
        var remaining = lines.filter { letters($0).count >= 2 }
        var picked: [Line] = []
        while picked.count < limit {
            let scored = remaining.map { line in (line, CGFloat(letters(line).subtracting(covered).count) * line.height) }
            guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 > 0 else { break }
            picked.append(best.0)
            covered.formUnion(letters(best.0))
            remaining.removeAll { $0.text == best.0.text && $0.corners == best.0.corners }
        }
        return picked
    }

    /// Le contour de Vision serre les lettres : on l'élargit pour garder les
    /// accents, les descendantes et un peu d'air autour.
    private static func expanded(_ line: Line) -> [CGPoint] {
        let c = line.corners
        let up = CGVector(dx: (c[0].x - c[3].x) / max(line.height, 1), dy: (c[0].y - c[3].y) / max(line.height, 1))
        let along = CGVector(dx: up.dy, dy: -up.dx)
        let v = line.height * 0.35, h = line.height * 0.4
        func move(_ p: CGPoint, _ a: CGFloat, _ b: CGFloat) -> CGPoint {
            CGPoint(x: p.x + up.dx * a + along.dx * b, y: p.y + up.dy * a + along.dy * b)
        }
        return [move(c[0], v, -h), move(c[1], v, h), move(c[2], -v, h), move(c[3], -v, -h)]
    }

    private static func isTilted(_ line: Line) -> Bool {
        let c = line.corners
        return abs(c[1].y - c[0].y) > line.height * 0.15
    }

    // MARK: Spécimens

    /// Les lignes de la capture composées dans une police, noir sur blanc,
    /// les unes sous les autres.
    static func specimen(_ lines: [String], font: CTFont, height: CGFloat = 96) -> Data? {
        let sized = CTFontCreateCopyWithAttributes(font, height, nil, nil)
        let rendered = lines.map { text -> (CTLine, CGRect) in
            let attributed = NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): sized,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            let line = CTLineCreateWithAttributedString(attributed)
            return (line, CTLineGetBoundsWithOptions(line, []))
        }
        let pad = height * 0.35, gap = height * 0.3
        let widest: CGFloat = rendered.map(\.1.width).max() ?? 0
        let stacked: CGFloat = rendered.map(\.1.height).reduce(0, +)
        let gaps: CGFloat = gap * CGFloat(max(0, rendered.count - 1))
        let width = Int(ceil(widest + pad * 2))
        let total = Int(ceil(stacked + gaps + pad * 2))
        guard !rendered.isEmpty, width > 0, total > 0, width < 8000,
              let context = CGContext(data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: total))
        // De haut en bas : Core Graphics compte depuis le bas.
        var top = CGFloat(total) - pad
        for (line, bounds) in rendered {
            context.textPosition = CGPoint(x: pad - bounds.minX, y: top - bounds.maxY)
            CTLineDraw(line, context)
            top -= bounds.height + gap
        }
        return context.makeImage().flatMap(png)
    }

    static func png(_ image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func image(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
