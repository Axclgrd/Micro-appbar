import SwiftUI

// Le vocabulaire visuel commun à tous les panneaux et fenêtres.
//
// Une règle de la charte d'Apple le résume : le verre est la couche des
// contrôles et de la navigation, jamais celle du contenu. Ici, le contenu
// reste sur des surfaces discrètes (`Groupe`), et le verre n'apparaît que sur
// ce qui flotte au-dessus (`verre`). Les contrôles standard (Button, Toggle,
// Picker, ProgressView…) prennent d'eux-mêmes l'apparence du système : on ne
// les redessine pas.

/// Rythme d'espacement, en multiples de 4 pt.
public enum Espace {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    /// Marge intérieure d'un panneau de la barre des menus.
    public static let panneau: CGFloat = 16
    /// Rayon d'une surface de contenu — concentrique avec celui du panneau.
    public static let rayon: CGFloat = 10
}

// MARK: - Verre

public extension View {
    /// Verre liquide sur macOS 26, matériau standard avant.
    ///
    /// À réserver aux éléments flottants et fonctionnels (barre, bouton
    /// flottant, étagère) : jamais sur le contenu, jamais verre sur verre.
    /// Plusieurs éléments voisins se posent dans un `GlassEffectContainer`.
    @ViewBuilder
    func verre<S: Shape>(_ forme: S, interactif: Bool = false) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(interactif ? .regular.interactive() : .regular, in: forme)
        } else {
            self.background(.regularMaterial, in: forme)
        }
    }

    /// Fond d'une surface de contenu : une teinte douce, pas du verre.
    func surface() -> some View {
        background(.quaternary.opacity(0.5), in: .rect(cornerRadius: Espace.rayon))
    }

    /// Survol d'une ligne cliquable : le retour que donne n'importe quelle
    /// liste macOS sous le pointeur.
    func survol(rayon: CGFloat = 7) -> some View {
        modifier(Survol(rayon: rayon))
    }
}

private struct Survol: ViewModifier {
    let rayon: CGFloat
    @State private var dessus = false

    func body(content: Content) -> some View {
        content
            .background(dessus ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: rayon))
            .onHover { dessus = $0 }
    }
}

// MARK: - Éléments

/// L'en-tête d'un panneau : un symbole, un verdict, une phrase d'explication.
public struct EnTete<Trailing: View>: View {
    let symbole: String
    let teinte: Color
    let titre: String
    let detail: String?
    let trailing: Trailing

    public init(symbole: String, teinte: Color = .accentColor, titre: String,
                detail: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.symbole = symbole
        self.teinte = teinte
        self.titre = titre
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Espace.m) {
            Image(systemName: symbole)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(teinte)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Espace.s)
            trailing
        }
        .accessibilityElement(children: .combine)
    }
}

public extension EnTete where Trailing == EmptyView {
    init(symbole: String, teinte: Color = .accentColor, titre: String, detail: String? = nil) {
        self.init(symbole: symbole, teinte: teinte, titre: titre, detail: detail) { EmptyView() }
    }
}

/// Un groupe de contenu : titre discret au-dessus, surface douce autour.
public struct Groupe<Content: View>: View {
    let titre: String?
    let content: Content

    public init(_ titre: String? = nil, @ViewBuilder content: () -> Content) {
        self.titre = titre
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Espace.xs) {
            if let titre {
                Text(titre)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Espace.xs)
            }
            VStack(alignment: .leading, spacing: Espace.s) {
                content
            }
            .padding(Espace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
        }
    }
}

/// Une ligne « libellé … valeur », la valeur en chiffres tabulaires pour ne
/// pas trembler quand elle change.
public struct Ligne: View {
    let libelle: String
    let valeur: String
    let aide: String?

    public init(_ libelle: String, _ valeur: String, aide: String? = nil) {
        self.libelle = libelle
        self.valeur = valeur
        self.aide = aide
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                Text(libelle)
                if let aide {
                    Text(aide)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: Espace.s)
            Text(valeur)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ce qu'on montre quand il n'y a rien à montrer.
public struct EtatVide: View {
    let symbole: String
    let titre: String
    let detail: String

    public init(symbole: String, titre: String, detail: String) {
        self.symbole = symbole
        self.titre = titre
        self.detail = detail
    }

    public var body: some View {
        VStack(spacing: Espace.xs) {
            Image(systemName: symbole)
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Text(titre).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Espace.l)
        .accessibilityElement(children: .combine)
    }
}

/// Le pied d'un panneau : une action discrète à gauche, Quitter à droite.
public struct PiedDePanneau<Leading: View>: View {
    let leading: Leading

    public init(@ViewBuilder leading: () -> Leading) {
        self.leading = leading()
    }

    public var body: some View {
        HStack {
            leading
            Spacer()
            Button("Quitter") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .font(.subheadline)
    }
}

public extension PiedDePanneau where Leading == EmptyView {
    init() { self.init { EmptyView() } }
}
