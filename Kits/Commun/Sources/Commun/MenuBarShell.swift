import AppKit
import Observation
import SwiftUI

/// La coquille d'une app autonome : une icône, un panneau, un outil.
///
/// C'est le même module que celui rangé dans Trousse, et donc le même panneau —
/// il n'existe qu'une seule fois. L'app autonome n'apporte que l'icône.
///
/// **Trousse a la priorité.** Si elle tourne, l'app autonome ne pose pas de
/// seconde icône : elle lui demande d'ouvrir l'outil et s'efface. Deux icônes
/// pour le même outil, avec deux sondages et deux panneaux qui peuvent se
/// contredire, ne rendrait service à personne.
@MainActor
public final class MenuBarShell: NSObject, NSPopoverDelegate {
    private let module: Module
    private let width: CGFloat
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var watcher: NSObjectProtocol?
    private let ailleurs = ClicAilleurs()

    public init(module: Module, width: CGFloat = 300) {
        self.module = module
        self.width = width
    }

    public func start() {
        if Presence.shared.trousseIsRunning {
            handOver()
            return
        }
        install()
        // Si la trousse démarre plus tard, on lui laisse la place à ce
        // moment-là plutôt que de doubler son icône.
        //
        // C'est la trousse qui s'annonce, et non `NSWorkspace` qui la signale :
        // ses notifications de lancement ne couvrent pas les apps agent, et la
        // trousse en est une — sans icône dans le Dock, elle démarrerait sans
        // que personne ne le sache.
        watcher = Shared.observe("trousse.hello") {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    }

    /// Demande à la trousse d'ouvrir cet outil, puis se retire.
    private func handOver() {
        Shared.broadcast("reveal.\(module.id)")
        // Laisse le temps à la notification de partir avant de mourir.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.terminate(nil)
        }
    }

    private func install() {
        follow()
    }

    private func place() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = module.title
        item.button?.target = self
        item.button?.action = #selector(toggle(_:))
        self.item = item
    }

    /// L'icône suit l'état de l'outil — la tasse d'Éveil se remplit, le temps
    /// restant s'affiche à côté. Le suivi est par observation, pas par horloge :
    /// il ne coûte rien tant que rien ne change.
    private func follow() {
        withObservationTracking {
            paint()
        } onChange: {
            Task { @MainActor [weak self] in self?.follow() }
        }
    }

    private func paint() {
        // L'outil peut demander à disparaître : on retire l'icône plutôt que
        // d'en laisser une inerte.
        guard module.isRelevant else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        if item == nil { place() }
        guard let button = item?.button else { return }
        // Un nom de symbole invalide ne lève rien : l'icône serait un vide, une
        // place occupée sans rien afficher, et l'app paraîtrait cassée.
        let image = NSImage(systemSymbolName: module.symbol, accessibilityDescription: module.title)
            ?? NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: module.title)
        image?.isTemplate = true
        button.image = image
        if let badge = module.badge {
            button.title = " \(badge)"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    @objc private func toggle(_ sender: NSStatusBarButton) {
        if popover != nil { close(); return }

        let panel = NSPopover()
        panel.behavior = .transient
        panel.animates = true
        panel.delegate = self
        panel.contentViewController = HotePopover.controleur(StandalonePanel(module: module), largeur: width)
        HotePopover.ouvrir(panel, sur: sender)
        popover = panel
        ailleurs.surveiller { [weak self] in self?.close() }
        module.activate()
    }

    private func close() {
        ailleurs.arreter()
        module.idle()
        popover?.performClose(nil)
        popover = nil
    }

    public nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.ailleurs.arreter()
            self?.module.idle()
            self?.popover = nil
        }
    }
}

/// Le panneau d'une app autonome : le panneau de l'outil, plus le titre et la
/// sortie que Trousse fournirait autrement.
private struct StandalonePanel: View {
    let module: Module

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(module.title).font(.callout.weight(.semibold))
                Spacer()
                Text(module.summary).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)

            module.makePanel()

            Divider().padding(.vertical, 2)

            Button("Quitter") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
        }
        .padding(.vertical, 10)
    }
}
