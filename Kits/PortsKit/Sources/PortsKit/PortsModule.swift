import AppKit
import Commun
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI

@MainActor
@Observable
public final class PortsModule: Module {
    public init() {}

    public let id = "ports"
    public let title = "Ports"
    public let symbol = "app.connected.to.app.below.fill"

    private(set) var listeners: [Listener] = []
    private(set) var scanning = false
    private(set) var address: String?

    /// Ce qui s'affiche dans le panneau du groupe, sans entrer dans l'outil.
    /// Seuls les serveurs qui t'appartiennent comptent : annoncer « 11 ports »
    /// en incluant les démons d'Apple ne dit rien d'utile.
    public var summary: String {
        let mine = listeners.filter { $0.verdict == .yours }.count
        if mine > 0 { return "\(mine) serveur\(mine > 1 ? "s" : "")" }
        return listeners.isEmpty ? "" : "\(listeners.count) ports"
    }

    private var timer: Timer?

    public func activate() {
        refresh()
        // Trois secondes : un serveur qu'on vient de tuer doit disparaître vite,
        // et la lecture est assez peu coûteuse pour qu'on puisse se le permettre
        // tant que le panneau est ouvert.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    public func idle() {
        timer?.invalidate()
        timer = nil
    }

    public func refresh() {
        guard !scanning else { return }
        scanning = true
        Task { [weak self] in
            let found = await Task.detached(priority: .utility) { PortsScanner.scan() }.value
            let local = await Task.detached(priority: .utility) { PortsScanner.localAddress() }.value
            guard let self else { return }
            listeners = found
            address = local
            scanning = false
        }
    }

    // MARK: Arrêter

    func stop(_ listener: Listener) {
        guard listener.verdict != .system else { return }
        _ = PortsScanner.stop(listener.pid)
        // On relit peu après : un serveur bien élevé met une fraction de seconde
        // à rendre la main, et la ligne doit disparaître d'elle-même.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.refresh()
        }
    }

    func force(_ listener: Listener) {
        guard listener.verdict != .system else { return }
        _ = PortsScanner.force(listener.pid)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.refresh()
        }
    }

    func url(for listener: Listener) -> String? {
        guard let address, listener.verdict != .system else { return nil }
        return "http://\(address):\(listener.port)"
    }

    /// Le QR du site en cours : viser avec le téléphone évite de taper une
    /// adresse IP à la main, ce qui est le seul vrai frein à tester sur mobile.
    func qr(for listener: Listener) -> NSImage? {
        guard let text = url(for: listener) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: 200, height: 200))
    }

    public func makePanel() -> AnyView {
        AnyView(PortsPanel(module: self))
    }
}
