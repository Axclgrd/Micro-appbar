import AppKit
import Observation
import Commun
import SwiftUI

/// Le propriétaire de la barre du haut.
///
/// C'est la raison d'être de la trousse : un seul processus tient autant
/// d'icônes que l'utilisateur a composé de groupes. Six apps séparées, c'était
/// six icônes imposées et six identités à autoriser ; ici c'est une identité et
/// le nombre d'icônes qu'on veut.
@MainActor
final class BarController: NSObject, NSPopoverDelegate {
    static let shared = BarController()

    private var items: [UUID: NSStatusItem] = [:]
    /// Le bouton d'un NSStatusItem ne sait pas à quel groupe il appartient :
    /// on tient la correspondance à côté.
    private var owners: [ObjectIdentifier: UUID] = [:]
    private var fallback: NSStatusItem?

    private var popover: NSPopover?
    private var shown: UUID?
    private let ailleurs = ClicAilleurs()

    func start() {
        rebuild()
        watch()
        follow()
    }

    /// Reconstruit dès que la composition change, sans que la fenêtre de
    /// réglages ait à prévenir qui que ce soit.
    private func watch() {
        withObservationTracking {
            _ = Config.shared.groups
        } onChange: {
            Task { @MainActor [weak self] in
                self?.rebuild()
                self?.watch()
            }
        }
    }

    // MARK: Les icônes

    private func rebuild() {
        let groups = Config.shared.groups

        for (id, item) in items where !groups.contains(where: { $0.id == id }) {
            owners[ObjectIdentifier(item.button ?? NSStatusBarButton())] = nil
            NSStatusBar.system.removeStatusItem(item)
            items[id] = nil
            if shown == id { close() }
        }

        for group in groups {
            let item = items[group.id] ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            items[group.id] = item
            guard let button = item.button else { continue }
            button.image = symbol(group.symbol, fallback: "square.grid.2x2", label: group.displayName)
            button.toolTip = group.displayName
            button.target = self
            button.action = #selector(toggle(_:))
            owners[ObjectIdentifier(button)] = group.id
        }

        // Sans aucun groupe, l'app deviendrait injoignable : plus d'icône, pas
        // d'icône dans le Dock non plus. Une icône de secours ouvre les réglages.
        if groups.isEmpty {
            if fallback == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.image = symbol("shippingbox", fallback: "gear", label: "Trousse")
                item.button?.toolTip = "Trousse — aucun groupe"
                item.button?.target = self
                item.button?.action = #selector(openSettings)
                fallback = item
            }
        } else if let item = fallback {
            NSStatusBar.system.removeStatusItem(item)
            fallback = nil
        }

        // Une icône qui vient d'apparaître porte son badge tout de suite,
        // plutôt que d'attendre que l'outil qui l'alimente change d'avis.
        paintBadges()
    }

    // MARK: Les badges

    /// Ce qu'un groupe montre à côté de son symbole : le temps restant d'Éveil,
    /// la température du point chaud.
    ///
    /// **Jusqu'à deux, puis plus rien.** Un groupe peut réunir plusieurs outils
    /// qui en réclament un — Machine tient les ventilateurs *et* Éveil. N'en
    /// montrer qu'un seul rendrait l'icône instable : la température
    /// disparaîtrait à l'instant où l'on active Éveil, sans raison lisible. On
    /// les affiche donc côte à côte, ce que leurs unités suffisent à
    /// distinguer — « 62° » n'est pas « 40m ». Au-delà de deux, la barre
    /// deviendrait un tableau de bord : on se tait.
    ///
    /// Les badges sont tous lus, même quand le troisième a déjà tranché : c'est
    /// cette lecture qui inscrit chaque outil auprès de l'observation, et donc
    /// ce qui fera revenir le badge quand l'un d'eux se taira.
    private func badge(of group: MenuGroup) -> String? {
        let badges = Config.shared.modules(of: group).compactMap(\.badge)
        guard !badges.isEmpty, badges.count <= 2 else { return nil }
        return badges.joined(separator: " ")
    }

    /// Le badge suit l'état des outils par observation, comme dans
    /// `MenuBarShell` : aucune horloge ne vient sonder ici, et un groupe dont
    /// rien ne bouge ne coûte rien.
    ///
    /// `onChange` prévient *avant* que la nouvelle valeur soit posée : on
    /// repeint au tour de boucle suivant, sinon on relirait l'ancienne.
    private func follow() {
        withObservationTracking {
            paintBadges()
        } onChange: {
            Task { @MainActor [weak self] in self?.follow() }
        }
    }

    private func paintBadges() {
        for group in Config.shared.groups {
            guard let button = items[group.id]?.button else { continue }
            if let badge = badge(of: group) {
                button.title = " \(badge)"
                button.imagePosition = .imageLeading
            } else {
                button.title = ""
                button.imagePosition = .imageOnly
            }
        }
    }

    private func symbol(_ name: String, fallback: String, label: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: fallback, accessibilityDescription: label)
        image?.isTemplate = true
        return image
    }

    // MARK: Le panneau

    @objc private func toggle(_ sender: NSStatusBarButton) {
        guard let id = owners[ObjectIdentifier(sender)],
              let group = Config.shared.groups.first(where: { $0.id == id })
        else { return }

        if shown == id { close(); return }
        close()

        let panel = NSPopover()
        panel.behavior = .transient
        panel.animates = true
        panel.delegate = self
        panel.contentViewController = HotePopover.controleur(GroupPanel(group: group), largeur: 300)
        HotePopover.ouvrir(panel, sur: sender)

        popover = panel
        shown = id
        ailleurs.surveiller { [weak self] in self?.close() }
        // Un outil ne sonde que pendant qu'on le regarde.
        for module in Config.shared.modules(of: group) { module.activate() }
    }

    /// Une app autonome lancée alors que la trousse tourne lui passe la main
    /// plutôt que de poser une seconde icône. C'est ici qu'on la reçoit.
    func reveal(_ moduleID: String) {
        // Un outil à fenêtre s'ouvre en grand : un popover se refermerait au
        // premier clic ailleurs, ce qui est exactement ce qu'on fait quand on
        // choisit un dossier ou qu'on dépose un fichier.
        if let module = Registry.shared.module(moduleID), module.hasWindow {
            NSApp.activate(ignoringOtherApps: true)
            module.open()
            return
        }
        // Un outil masqué n'appartient à aucun groupe. Le refuser ici voudrait
        // dire que lancer Grab.app, alors qu'il est rangé dans les masqués, ne
        // ferait rien du tout : l'app autonome se retire, et personne ne prend
        // le relais. On l'accroche donc à la première icône venue.
        let group = Config.shared.group(containing: moduleID)
            ?? MenuGroup(name: Registry.shared.module(moduleID)?.title ?? "Outil",
                         symbol: "square.grid.2x2", modules: [moduleID])
        guard let button = items[group.id]?.button
            ?? items[Config.shared.groups.first?.id ?? group.id]?.button
            ?? fallback?.button
        else { return }

        close()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSPopover()
        panel.behavior = .transient
        panel.animates = true
        panel.delegate = self
        panel.contentViewController = HotePopover.controleur(GroupPanel(group: group, initial: moduleID), largeur: 300)
        HotePopover.ouvrir(panel, sur: button)
        popover = panel
        shown = group.id
        ailleurs.surveiller { [weak self] in self?.close() }
        for module in Config.shared.modules(of: group) { module.activate() }
        Registry.shared.module(moduleID)?.activate()
    }

    @objc private func openSettings() {
        Dashboard.shared.show()
    }

    private func close() {
        ailleurs.arreter()
        if let id = shown, let group = Config.shared.groups.first(where: { $0.id == id }) {
            for module in Config.shared.modules(of: group) { module.idle() }
        }
        popover?.performClose(nil)
        popover = nil
        shown = nil
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.ailleurs.arreter()
            guard let self, let id = shown,
                  let group = Config.shared.groups.first(where: { $0.id == id }) else { return }
            for module in Config.shared.modules(of: group) { module.idle() }
            popover = nil
            shown = nil
        }
    }
}
