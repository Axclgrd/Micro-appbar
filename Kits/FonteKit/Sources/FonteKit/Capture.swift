import AppKit
import ImageIO
import UniformTypeIdentifiers

/// La sélection à l'écran.
///
/// Déléguée à `screencapture`, comme dans Grab et pour les mêmes raisons :
/// c'est l'outil du système, donc la même croix, les mêmes touches (espace
/// pour viser une fenêtre, Échap pour annuler) et le même comportement
/// multi-écran que ⇧⌘4.
enum ScreenSelection {

    enum Outcome: Sendable {
        case image(Data)
        case cancelled
        case denied
    }

    static func run() -> Outcome {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "fonte-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-o", "-t", "png", file.path]
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .denied
        }
        process.waitUntilExit()

        // Échap pendant la sélection : le processus sort sans écrire de
        // fichier. C'est la seule façon de reconnaître l'annulation.
        guard FileManager.default.fileExists(atPath: file.path) else { return .cancelled }
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return .denied }

        // Un refus d'autorisation ne ressemble pas à un refus : `screencapture`
        // écrit un PNG valide, entièrement noir. Sans ce contrôle, on
        // demanderait à Claude de reconnaître une police dans un rectangle noir.
        if isBlank(data) { return .denied }
        return .image(data)
    }

    /// L'image est-elle uniformément noire ? Une vraie sélection de texte
    /// porte toujours des nuances : on échantillonne une grille, une seule
    /// valeur non noire suffit à conclure.
    static func isBlank(_ data: Data) -> Bool {
        guard let bitmap = NSBitmapImageRep(data: data) else { return false }
        let stepX = max(1, bitmap.pixelsWide / 32)
        let stepY = max(1, bitmap.pixelsHigh / 32)
        for x in stride(from: 0, to: bitmap.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: stepY) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.04 || color.greenComponent > 0.04 || color.blueComponent > 0.04 {
                    return false
                }
            }
        }
        return true
    }
}

/// Les images telles qu'on les garde et qu'on les envoie.
enum Picture {

    /// Au-delà, Claude réduirait l'image lui-même : autant envoyer moins. En
    /// deçà, on ne touche à rien — chaque pixel d'un empattement compte.
    static let maxSide = 2000

    /// L'image en PNG, réduite si elle dépasse `maxSide`. `nil` si les
    /// données ne sont pas une image : un fichier lâché par erreur, un PDF.
    static func normalized(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        let image: CGImage?
        if max(width, height) > maxSide {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSide,
            ] as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        // La densité d'origine est gardée : une capture Retina reste affichée
        // à sa taille réelle à l'écran, pas au double.
        var metadata: [CFString: Any] = [:]
        if max(width, height) <= maxSide {
            metadata[kCGImagePropertyDPIWidth] = properties[kCGImagePropertyDPIWidth]
            metadata[kCGImagePropertyDPIHeight] = properties[kCGImagePropertyDPIHeight]
        }
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
