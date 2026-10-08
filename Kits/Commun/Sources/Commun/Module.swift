import SwiftUI

/// Ce qu'un outil doit fournir pour être affichable — par Trousse comme par sa
/// propre app autonome.
///
/// Un outil est écrit une fois, dans sa bibliothèque. Trousse le range dans un
/// groupe ; son app autonome lui donne une icône à lui. Les deux affichent
/// exactement le même panneau, parce que c'est le même objet.
@MainActor
public protocol Module: AnyObject {
    /// Identifiant stable : c'est lui qui rattache un outil à son groupe dans
    /// la configuration. Il ne doit jamais changer.
    var id: String { get }
    var title: String { get }
    var symbol: String { get }

    /// La ligne d'état, lisible sans entrer dans l'outil : « 3 serveurs »,
    /// « 1 850 tr/min », « active jusqu'à 18 h ». Vide quand il n'y a rien à dire.
    var summary: String { get }

    /// L'outil s'ouvre-t-il dans une vraie fenêtre ?
    ///
    /// Purge et Bande demandent à lire avant d'agir : leur panneau n'est qu'un
    /// raccourci vers leur fenêtre. Quand on les appelle, c'est elle qu'il faut
    /// ouvrir, pas un popover qui se refermerait au premier clic ailleurs.
    var hasWindow: Bool { get }
    func open()

    /// L'outil a-t-il quelque chose à montrer en ce moment ?
    ///
    /// Ejecter dit non quand aucun disque externe n'est branché, Grab dit non
    /// quand on a masqué son icône. Sur un écran à encoche, une place
    /// permanente pour un outil qui n'a rien à dire est une place prise à un
    /// autre. Sans effet dans Trousse : c'est le groupe qui possède l'icône.
    var isRelevant: Bool { get }

    /// Ce que l'icône montre en plus du symbole — le temps restant d'Éveil,
    /// par exemple. `nil` pour la plupart des outils, et c'est le défaut.
    var badge: String? { get }

    /// Sondage : allumé tant qu'un panneau qui montre cet outil est ouvert,
    /// éteint sinon. Un outil qu'on ne regarde pas ne doit rien coûter.
    func activate()
    func idle()

    func makePanel() -> AnyView
}

public extension Module {
    var hasWindow: Bool { false }
    func open() {}
    var isRelevant: Bool { true }
    var badge: String? { nil }
    func activate() {}
    func idle() {}
}
