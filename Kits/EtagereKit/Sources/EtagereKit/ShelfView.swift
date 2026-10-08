import AppKit
import Commun
import QuickLookThumbnailing
import SwiftUI

private extension Metric {
    /// Rayon d'une vignette ; celui de la tablette en découle (vignette + marge).
    static let tileRadius: CGFloat = 12
}

/// La tablette.
///
/// Toute la vue est dessinée *sous* la ligne de l'encoche : la fenêtre couvre
/// bien l'encoche elle-même — c'est ce qui en fait une cible de glisser
/// gratuite — mais aucun pixel n'y est visible, puisqu'il n'y a pas d'écran
/// derrière. D'où le premier bloc, un vide de la hauteur de l'encoche.
struct ShelfView: View {
    let shelf: Shelf
    let geometry: ShelfGeometry
    let link: ShelfLink

    @Environment(\.accessibilityReduceTransparency) private var opaque

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: geometry.notchHeight)
            ZStack(alignment: .top) {
                lip
                tablet
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    // MARK: - L'éveil et le souvenir

    /// Les deux tiennent au même trait sous l'encoche, et c'est voulu : ils
    /// disent la même chose — « il se passe quelque chose ici ». L'éveil est
    /// large comme l'encoche et dure le temps d'un glisser ; le souvenir est
    /// étroit et reste.
    private var lipHeight: CGFloat {
        switch shelf.phase {
        case .awake: return Metric.awakeThickness
        case .closed: return shelf.items.isEmpty ? 0 : Metric.bulgeThickness
        case .open: return 0
        }
    }

    /// Largeur au raccord. L'éveil prend presque toute l'encoche, mais reste
    /// en deçà de ses coins arrondis : les congés doivent tomber sur la partie
    /// droite du bord, sinon ils raccordent une courbe à une autre courbe.
    private var lipSpan: CGFloat {
        shelf.phase == .awake ? max(geometry.lipWidth - 24, 80) : Metric.bulgeWidth
    }

    /// La part de la largeur donnée aux congés. Pour le souvenir elle prend
    /// presque tout : il ne reste qu'un fond plat de quelques points, et la
    /// forme devient une houle plutôt qu'une languette.
    private var lipFlare: CGFloat {
        shelf.phase == .awake ? 16 : 24
    }

    /// Ce qui remonte derrière l'encoche : juste de quoi couvrir un arrondi de
    /// calcul, pas plus. Deux points suffisent à garantir qu'aucune couture
    /// d'un demi-pixel n'apparaisse au raccord — et remonter davantage n'aurait
    /// aucun effet à l'écran, où le boîtier de la caméra cache tout, mais
    /// dessinerait une languette noire bien visible sur les captures d'écran,
    /// qui, elles, montrent le fond d'écran sous l'encoche.
    private var lipRise: CGFloat { geometry.hasNotch ? 2 : 0 }

    private var lip: some View {
        NotchLip(span: lipSpan, depth: lipHeight, rise: lipRise, flare: lipFlare)
            // Noir plein sur un écran à encoche : le bourrelet doit être fait
            // de la même matière que le boîtier de la caméra, pas posé à côté.
            // Sur un écran sans encoche il n'y a rien à prolonger, donc rien à
            // imiter — et un noir opaque y serait une tache.
            .fill(Color.black.opacity(geometry.hasNotch ? 1 : 0.78))
            .frame(width: lipSpan, height: lipHeight + lipRise)
            .offset(y: -lipRise)
            .frame(width: lipSpan, height: max(lipHeight, 0), alignment: .top)
            .animation(shelf.phase == .awake ? Motion.wake : Motion.fold, value: lipHeight)
            .animation(Motion.shift, value: lipSpan)
    }

    // MARK: - Le dépliage

    private var displayedCount: Int {
        shelf.items.count + (shelf.insertion != nil ? 1 : 0)
    }

    private var tabletWidth: CGFloat { Metric.width(for: displayedCount) }

    private var deployed: CGFloat { shelf.phase == .open ? Metric.shelfHeight : 0 }

    /// Le tiroir. La tablette garde toujours sa taille finale ; c'est la
    /// fenêtre découpée devant elle qui grandit, et le contenu, aligné sur le
    /// bas, descend avec. Un fondu à la place donnerait une tablette qui
    /// apparaît au milieu de rien — exactement ce qu'il fallait éviter.
    private var tablet: some View {
        board
            .frame(width: tabletWidth, height: Metric.shelfHeight)
            .frame(width: tabletWidth, height: deployed, alignment: .bottom)
            .clipped()
            .shadow(color: .black.opacity(0.42 * Double(deployed / Metric.shelfHeight)),
                    radius: 14, y: 7)
            .animation(shelf.phase == .open ? Motion.unfold : Motion.fold, value: deployed)
            .animation(Motion.shift, value: tabletWidth)
    }

    /// Rayon extérieur = rayon de la vignette + marge : les coins de la
    /// tablette et ceux des vignettes restent concentriques (HIG, Layout).
    private var surface: some InsettableShape {
        let radius = Metric.tileRadius + Metric.pad
        return UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius,
                                      style: .continuous)
    }

    /// La tablette est la seule couche fonctionnelle : elle flotte au-dessus
    /// des autres apps, donc elle a droit au verre. Les vignettes restent du
    /// contenu, posé dessus sans verre propre. « Réduire la transparence » la
    /// remplace par un aplat opaque.
    @ViewBuilder
    private var backing: some View {
        if opaque {
            surface.fill(Color(nsColor: .windowBackgroundColor))
            surface.strokeBorder(.separator, lineWidth: 1)
        } else if #available(macOS 26, *) {
            GlassEffectContainer {
                Color.clear.verre(surface)
            }
        } else {
            Color.clear.verre(surface)
            surface.strokeBorder(.separator, lineWidth: 1)
        }
    }

    private var board: some View {
        HStack(spacing: Metric.gap) {
            if slots.isEmpty {
                Label("Montez un fichier jusqu'ici", systemImage: "tray.and.arrow.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(slots) { slot in
                    switch slot {
                    case .gap: hollow
                    case .item(let item):
                        ItemTile(item: item, link: link, lifted: shelf.lifted == item.id)
                    }
                }
            }
        }
        .padding(Metric.pad)
        .frame(width: tabletWidth, height: Metric.shelfHeight)
        .background { backing }
        .animation(Motion.shift, value: slots.map(\.id))
    }

    /// La place qui se creuse sous le curseur.
    ///
    /// Teinte d'accent : c'est le retour de cible de dépôt attendu par la
    /// charte — « ici, ça sera reçu » — et non un simple pointillé gris.
    private var hollow: some View {
        RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
            .fill(Color.accentColor.opacity(0.14))
            .strokeBorder(Color.accentColor.opacity(0.7),
                          style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .frame(width: Metric.tile, height: Metric.tile)
            .accessibilityHidden(true)
    }

    private enum Slot: Identifiable {
        case gap
        case item(ShelfItem)

        var id: String {
            switch self {
            case .gap: return "creux"
            case .item(let item): return item.id.uuidString
            }
        }
    }

    private var slots: [Slot] {
        var result = shelf.items.map(Slot.item)
        if let index = shelf.insertion {
            result.insert(.gap, at: min(max(index, 0), result.count))
        }
        return result
    }
}

// MARK: - Les gestes sur un objet

/// Les mêmes gestes pour le menu contextuel, VoiceOver et le panneau.
@MainActor
enum ItemActions {
    static func open(_ item: ShelfItem) {
        guard !item.missing else { return }
        NSWorkspace.shared.open(item.url)
    }

    static func reveal(_ item: ShelfItem) {
        guard !item.missing else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    static func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
    }

    static func remove(_ item: ShelfItem) {
        Shelf.shared.remove(item.id)
    }
}

// MARK: - Un objet posé

private struct ItemTile: View {
    let item: ShelfItem
    let link: ShelfLink
    let lifted: Bool

    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var image: NSImage?
    @State private var hovering = false

    var body: some View {
        Group {
            if item.landing && !reduce {
                KeyframeAnimator(initialValue: Fall(), trigger: item.id) { value in
                    face
                        .offset(y: value.height)
                        .shadow(color: .black.opacity(0.38 * value.shade),
                                radius: 5 * value.shade, y: 3 * value.shade)
                } keyframes: { _ in
                    // Le seul rebond de tout l'outil : la chute, un
                    // dépassement de trois points et demi, et c'est posé.
                    // Un ressort ferait le même geste en moins net et en
                    // rebondissant deux fois — ici la troisième image est la
                    // dernière.
                    KeyframeTrack(\.height) {
                        CubicKeyframe(0, duration: 0.11)
                        CubicKeyframe(-3.5, duration: 0.06)
                        CubicKeyframe(0, duration: 0.06)
                    }
                    // L'ombre naît pendant la chute et reste : c'est elle qui
                    // pose l'objet sur la tablette plutôt que devant.
                    KeyframeTrack(\.shade) {
                        LinearKeyframe(1, duration: 0.11)
                        LinearKeyframe(1, duration: 0.12)
                    }
                }
            } else {
                face.shadow(color: .black.opacity(0.38), radius: 5, y: 3)
            }
        }
        .scaleEffect(lifted ? 1.07 : 1)
        .shadow(color: .black.opacity(lifted ? 0.55 : 0), radius: lifted ? 13 : 0, y: lifted ? 9 : 0)
        .animation(Motion.lift, value: lifted)
        .task(id: item.url.path) {
            guard !item.missing else { return }
            image = await Thumbs.load(item.url)
        }
    }

    private struct Fall {
        /// L'objet part neuf points au-dessus de sa place.
        var height: CGFloat = -9
        var shade: Double = 0
    }

    private var face: some View {
        VStack(spacing: 4) {
            preview
                .frame(width: 40, height: 40)
            Text(item.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(item.missing ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .padding(.horizontal, Espace.xs)
        }
        .frame(width: Metric.tile, height: Metric.tile)
        .background {
            // Du contenu, pas du verre : une teinte qui s'éclaircit au survol.
            RoundedRectangle(cornerRadius: Metric.tileRadius, style: .continuous)
                .fill(Color.primary.opacity(hovering || lifted ? 0.14 : 0.07))
        }
        .overlay {
            DragHandle(item: item, link: link)
        }
        .onHover { hovering = $0 }
        .animation(Motion.lift, value: hovering)
        .help(item.missing ? "\(item.url.path) — introuvable" : item.url.path)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityValue(item.missing ? "introuvable" : "")
        .accessibilityHint(item.missing ? "" : "Glissez pour déposer ailleurs, ou ouvrez avec les actions.")
        .accessibilityAction(named: "Ouvrir") { ItemActions.open(item) }
        .accessibilityAction(named: "Afficher dans le Finder") { ItemActions.reveal(item) }
        .accessibilityAction(named: "Copier le chemin") { ItemActions.copyPath(item) }
        .accessibilityAction(named: "Retirer de l'étagère") { ItemActions.remove(item) }
    }

    @ViewBuilder
    private var preview: some View {
        if item.missing {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 26))
                .foregroundStyle(.red)
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "doc")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Les vignettes, une fois chacune.
///
/// QuickLook rend l'aperçu réel d'une image ou d'un PDF là où l'icône de
/// document ne dirait rien : sur une tablette de soixante-douze points, ce qui
/// distingue deux captures d'écran, c'est leur contenu, pas leur nom tronqué.
@MainActor
enum Thumbs {
    private static var cache: [String: NSImage] = [:]

    static func load(_ url: URL) async -> NSImage {
        if let hit = cache[url.path] { return hit }
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 80, height: 80), scale: 2,
            representationTypes: .all)
        if let made = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            cache[url.path] = made.nsImage
            return made.nsImage
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = icon
        return icon
    }
}

// MARK: - La reprise

/// La poignée qui rend l'objet au système.
///
/// En AppKit et non en `.onDrag` : SwiftUI démarre bien le glisser, mais ne dit
/// jamais comment il finit. Sans cette fin, impossible de savoir si l'objet a
/// été reçu — et un objet retiré de l'étagère alors que le glisser a été
/// abandonné en route, c'est une perte silencieuse.
private struct DragHandle: NSViewRepresentable {
    let item: ShelfItem
    let link: ShelfLink

    func makeNSView(context: Context) -> DragHandleView {
        let view = DragHandleView()
        view.item = item
        view.link = link
        return view
    }

    func updateNSView(_ view: DragHandleView, context: Context) {
        view.item = item
        view.link = link
    }
}

final class DragHandleView: NSView, NSDraggingSource {
    var item: ShelfItem?
    var link: ShelfLink?

    override func mouseDown(with event: NSEvent) {
        guard let item, !item.missing else { return }
        if event.clickCount >= 2 {
            NSWorkspace.shared.open(item.url)
            return
        }

        // On attend le seuil de glisser avant d'ouvrir la session : démarrer
        // dès l'appui rendrait tout clic impossible, y compris le double-clic
        // qui ouvre le fichier.
        let origin = event.locationInWindow
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp { return }
            let travel = hypot(next.locationInWindow.x - origin.x,
                               next.locationInWindow.y - origin.y)
            if travel > 3 {
                begin(drag: next, item: item)
                return
            }
        }
    }

    private func begin(drag event: NSEvent, item: ShelfItem) {
        let dragged = NSDraggingItem(pasteboardWriter: item.url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: 48, height: 48)
        dragged.setDraggingFrame(
            NSRect(x: bounds.midX - 24, y: bounds.midY - 24, width: 48, height: 48),
            contents: icon)
        beginDraggingSession(with: [dragged], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .link, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt point: NSPoint) {
        guard let item else { return }
        MainActor.assumeIsolated { link?.controller?.lift(item.id) }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt point: NSPoint,
                         operation: NSDragOperation) {
        guard let item else { return }
        MainActor.assumeIsolated {
            link?.controller?.settle(item.id, accepted: !operation.isEmpty)
        }
    }

    // MARK: Le menu contextuel

    /// Pas de petite croix sur la vignette : à soixante-douze points, elle
    /// mangerait la place de ce qu'on regarde, et on la viserait mal.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let item else { return nil }
        let menu = NSMenu()
        if !item.missing {
            menu.addItem(withTitle: "Ouvrir", action: #selector(openItem), keyEquivalent: "")
            menu.addItem(withTitle: "Afficher dans le Finder", action: #selector(revealItem), keyEquivalent: "")
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Copier le chemin", action: #selector(copyItemPath), keyEquivalent: "")
        menu.addItem(withTitle: "Retirer de l'étagère", action: #selector(removeItem), keyEquivalent: "")
        for entry in menu.items { entry.target = self }
        return menu
    }

    @objc private func openItem() {
        guard let item else { return }
        NSWorkspace.shared.open(item.url)
    }

    @objc private func revealItem() {
        guard let item else { return }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    @objc private func copyItemPath() {
        guard let item else { return }
        MainActor.assumeIsolated { ItemActions.copyPath(item) }
    }

    @objc private func removeItem() {
        guard let item else { return }
        MainActor.assumeIsolated { Shelf.shared.remove(item.id) }
    }
}
