import AppKit
import Commun
import Observation
import SwiftUI

/// La fenêtre-tablette, et la zone sensible qui la réveille.
///
/// Une seule fenêtre pour les deux : elle est minuscule quand la tablette dort
/// et grandit quand elle s'ouvre. C'est délibéré. Une fenêtre invisible qui
/// resterait grande en permanence en haut de l'écran avalerait les clics
/// destinés à la fenêtre du dessous — le pire défaut possible pour un outil
/// censé se faire oublier.
@MainActor
final class ShelfController: NSObject {
    private let shelf: Shelf
    private var panel: NSPanel?
    private var drop: DropView?
    private var geometry = ShelfGeometry.current()
    private let link = ShelfLink()

    /// Un glisser survole la tablette.
    private var dragOver = false
    /// La souris est posée sur la zone sensible.
    private var inside = false
    /// Jusqu'à quand la tablette reste ouverte quoi qu'il arrive — le temps de
    /// voir l'objet se poser avant que tout ne rentre.
    private var holdUntil = Date.distantPast
    private var holdTimer: Timer?
    private var hoverTask: Task<Void, Never>?

    init(shelf: Shelf = .shared) {
        self.shelf = shelf
        super.init()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screensChanged() }
            }
    }

    func start() {
        DragWatch.shared.start()
        build()
        follow()
        greet()
    }

    /// Au tout premier lancement, la tablette sort une seconde d'elle-même.
    ///
    /// Un outil qui n'existe que sous l'encoche et ne se manifeste qu'au
    /// glisser est parfaitement invisible pour qui ne connaît pas le geste :
    /// on l'installe, il ne se passe rien, on le désinstalle. Une fois, au
    /// début, il montre où il habite.
    private func greet() {
        guard !Shared.defaults.bool(forKey: "etagere.greeted") else { return }
        Shared.defaults.set(true, forKey: "etagere.greeted")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            self?.reveal()
        }
    }

    // MARK: - La fenêtre

    private func build() {
        let panel = NSPanel(contentRect: geometry.frame(width: geometry.lipWidth, depth: geometry.idleDepth),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        // Au-dessus des fenêtres ordinaires, jamais au-dessus de la barre des
        // menus : la tablette sort *sous* l'encoche, elle n'a rien à recouvrir.
        panel.level = .statusBar
        // La tablette doit traverser les changements d'app, de bureau et le
        // plein écran — c'est la moitié de sa raison d'être.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = false

        let view = DropView(frame: panel.contentRect(forFrameRect: panel.frame))
        view.controller = self
        view.shelf = shelf
        link.controller = self
        let host = NSHostingView(rootView: ShelfView(shelf: shelf, geometry: geometry, link: link))
        host.autoresizingMask = [.width, .height]
        host.frame = view.bounds
        view.addSubview(host)
        panel.contentView = view

        self.panel = panel
        self.drop = view
        layout(animated: false)
        panel.orderFrontRegardless()
    }

    /// Suit l'état par observation plutôt qu'à l'horloge : rien ne bouge tant
    /// que rien ne change.
    private func follow() {
        withObservationTracking {
            _ = shelf.phase
            _ = shelf.items.count
            _ = shelf.enabled
            _ = DragWatch.shared.lifted
        } onChange: {
            Task { @MainActor [weak self] in
                self?.reconsider()
                self?.layout(animated: true)
                self?.follow()
            }
        }
    }

    private func screensChanged() {
        geometry = ShelfGeometry.current()
        if let drop, let host = drop.subviews.first as? NSHostingView<ShelfView> {
            host.rootView = ShelfView(shelf: shelf, geometry: geometry, link: link)
        }
        layout(animated: false)
    }

    // MARK: - Décider de l'état

    /// Un seul endroit décide de l'état de la tablette, à partir de ce qui est
    /// vrai à cet instant. Répartir cette décision entre les évènements de
    /// glisser et de survol, c'est se garantir un état qui se coince.
    func reconsider() {
        guard shelf.enabled else {
            shelf.phase = .closed
            panel?.orderOut(nil)
            return
        }
        if panel?.isVisible == false { panel?.orderFrontRegardless() }

        let held = Date() < holdUntil
        let wanted: Shelf.Phase
        if dragOver || shelf.lifted != nil || held || (inside && !shelf.items.isEmpty) {
            wanted = .open
        } else if DragWatch.shared.lifted {
            wanted = .awake
        } else {
            wanted = .closed
        }
        guard wanted != shelf.phase else { return }
        if wanted == .open { shelf.verifyAll() }
        if wanted != .open { shelf.insertion = nil }
        shelf.phase = wanted
    }

    /// Montre la tablette de son propre chef, le temps de la voir.
    ///
    /// Un outil qui vit sous l'encoche et ne se manifeste qu'au glisser est
    /// invisible tant qu'on ne connaît pas le geste. C'est le seul endroit d'où
    /// on peut le montrer.
    func reveal() {
        hold(2.5)
        reconsider()
        layout(animated: true)
    }

    /// Tient la tablette ouverte encore un moment — le temps du rebond.
    private func hold(_ seconds: TimeInterval) {
        holdUntil = Date().addingTimeInterval(seconds)
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: seconds + 0.02, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reconsider()
                self?.layout(animated: true)
            }
        }
    }

    // MARK: - Le cadre

    private var wantedFrame: NSRect {
        switch shelf.phase {
        case .closed:
            // Étagère vide sur un écran à encoche : la fenêtre se réduit à
            // l'encoche exacte, où aucun clic ne sert à rien. L'outil au repos
            // ne prend alors rigoureusement rien à personne. Les cinq points
            // sous l'encoche ne sont repris que quand il y a un renflement à
            // dessiner.
            let depth = shelf.items.isEmpty && geometry.hasNotch ? 0 : geometry.idleDepth
            return geometry.frame(width: max(geometry.lipWidth, Metric.bulgeWidth), depth: depth)
        case .awake:
            return geometry.frame(width: geometry.lipWidth + Metric.catchWings * 2, depth: Metric.catchDepth)
        case .open:
            // Une place de plus que d'objets : la tablette s'élargit d'un cran
            // quand la place se creuse, et la fenêtre ne doit pas la rogner en
            // plein mouvement.
            let width = Metric.width(for: shelf.items.count + 1) + Metric.shadow * 2
            return geometry.frame(width: width, depth: Metric.shelfHeight + Metric.shadow)
        }
    }

    /// Le cadre de la fenêtre saute, il ne s'anime pas : c'est le contenu qui
    /// se déplie. Animer un cadre de fenêtre à soixante images par seconde
    /// saccade, et le pli sortirait du cadre pendant la moitié du trajet.
    private func layout(animated: Bool) {
        guard let panel, let drop else { return }
        let target = wantedFrame
        let shrinking = target.height < panel.frame.height

        let apply = { [weak self] in
            guard let self, let panel = self.panel else { return }
            panel.setFrame(target, display: true)
            drop.active = self.activeRect(in: target)
            drop.window?.invalidateCursorRects(for: drop)
            // Le cadre a bougé sous la souris : la zone de survol n'est plus la
            // même, il faut la relire plutôt que d'attendre un mouvement.
            self.inside = drop.active
                .offsetBy(dx: target.minX, dy: target.minY)
                .contains(NSEvent.mouseLocation)
        }

        if shrinking && animated {
            // On laisse au repli le temps de rentrer avant de reprendre la
            // place : sinon la fenêtre se coupe au premier tiers du mouvement.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Motion.reduced ? 0 : 170))
                guard self.wantedFrame == target else { return }
                apply()
            }
        } else {
            apply()
        }
    }

    /// La partie de la fenêtre qui prend réellement la souris. Le reste — la
    /// réserve d'ombre sur les côtés — laisse passer les clics.
    private func activeRect(in frame: NSRect) -> NSRect {
        let bounds = NSRect(origin: .zero, size: frame.size)
        guard shelf.phase == .open else { return bounds }
        return NSRect(x: Metric.shadow, y: Metric.shadow,
                      width: bounds.width - Metric.shadow * 2,
                      height: bounds.height - Metric.shadow)
    }

    // MARK: - Ce que la vue de dépôt raconte

    func dragEntered(at index: Int) {
        dragOver = true
        shelf.insertion = index
        reconsider()
        layout(animated: true)
    }

    func dragMoved(to index: Int) {
        guard shelf.insertion != index else { return }
        shelf.insertion = index
    }

    func dragLeft() {
        dragOver = false
        shelf.insertion = nil
        reconsider()
        layout(animated: true)
    }

    func dropped(_ pasteboard: NSPasteboard, at index: Int) -> Bool {
        let added = shelf.accept(pasteboard, at: index)
        dragOver = false
        shelf.insertion = nil
        // Assez pour voir le rebond et l'ombre naître, pas assez pour rester
        // dans les pattes.
        hold(added > 0 ? 0.6 : 0.2)
        reconsider()
        layout(animated: true)
        return added > 0
    }

    func mouseEntered() {
        hoverTask?.cancel()
        guard !shelf.items.isEmpty, shelf.phase != .open else {
            inside = true
            return
        }
        // Un temps mort avant d'ouvrir : sans lui, la tablette se déplierait
        // chaque fois que le curseur traverse le haut de l'écran.
        hoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled, let self else { return }
            self.inside = true
            self.reconsider()
            self.layout(animated: true)
        }
    }

    func mouseExited() {
        hoverTask?.cancel()
        inside = false
        reconsider()
        layout(animated: true)
    }

    func lift(_ id: ShelfItem.ID) {
        shelf.lifted = id
        reconsider()
    }

    /// Fin de la reprise. L'objet ne quitte l'étagère que si quelqu'un l'a
    /// vraiment reçu : un glisser abandonné en route le repose.
    func settle(_ id: ShelfItem.ID, accepted: Bool) {
        shelf.lifted = nil
        if accepted { shelf.remove(id) }
        reconsider()
        layout(animated: true)
    }
}

/// La vue qui reçoit les glissers et le survol.
final class DropView: NSView {
    weak var controller: ShelfController?
    var shelf: Shelf?

    /// La zone qui prend la souris, en coordonnées de la vue.
    var active: NSRect = .zero {
        didSet { if active != oldValue { updateTrackingAreas() } }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([
            .fileURL, .URL, .string, .tiff, .png,
            NSPasteboard.PasteboardType("public.image"),
        ])
    }

    required init?(coder: NSCoder) { nil }

    /// Hors de la zone active, la fenêtre n'existe pas pour la souris : le clic
    /// va à ce qu'il y a dessous.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard active.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        guard active.width > 0 else { return }
        addTrackingArea(NSTrackingArea(rect: active,
                                       options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.mouseEntered() }
    }

    override func mouseExited(with event: NSEvent) {
        MainActor.assumeIsolated { controller?.mouseExited() }
    }

    // MARK: Glisser

    /// L'opération annoncée au curseur. « Générique » d'abord, parce que
    /// l'étagère ne copie ni ne déplace rien : elle retient un chemin. Afficher
    /// le « + » de la copie promettrait un fichier dupliqué qui n'existera pas.
    private func operation(for sender: NSDraggingInfo) -> NSDragOperation {
        let allowed = sender.draggingSourceOperationMask
        for candidate in [NSDragOperation.generic, .copy, .link] where allowed.contains(candidate) {
            return candidate
        }
        return []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { controller?.dragEntered(at: index(for: sender)) }
        return operation(for: sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { controller?.dragMoved(to: index(for: sender)) }
        return operation(for: sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated { controller?.dragLeft() }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated {
            controller?.dropped(sender.draggingPasteboard, at: index(for: sender)) ?? false
        }
    }

    /// La place qui se creuse : celle sur laquelle le curseur est posé, la
    /// disposition étant calculée avec l'emplacement supplémentaire déjà ouvert.
    private func index(for sender: NSDraggingInfo) -> Int {
        MainActor.assumeIsolated {
            let count = shelf?.items.count ?? 0
            let point = convert(sender.draggingLocation, from: nil)
            let width = Metric.width(for: count + 1)
            let originX = (bounds.width - width) / 2 + Metric.pad
            let step = Metric.tile + Metric.gap
            let raw = (point.x - originX) / step
            return min(max(Int(raw.rounded(.down)), 0), count)
        }
    }
}
