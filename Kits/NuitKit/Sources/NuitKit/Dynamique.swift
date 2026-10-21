import Foundation

/// Le traitement : nivelleur lent → compresseur → limiteur à anticipation.
///
/// Écrit à la main plutôt qu'en Audio Units Apple (DynamicsProcessor +
/// PeakLimiter) : pas de graphe AVAudioEngine à tenir, pas de tampon
/// supplémentaire, et une latence connue au échantillon près — l'anticipation du
/// limiteur, `anticipation` ms, et rien d'autre.
///
/// Appelé depuis le fil temps réel de CoreAudio : aucune allocation, aucun
/// verrou, aucun appel Objective-C. Les réglages sont écrits depuis le fil
/// principal sans synchronisation ; une lecture déchirée entre deux champs ne
/// donne qu'une valeur transitoire dans les bornes, jamais un NaN.
public final class Dynamique: @unchecked Sendable {
    public struct Reglage: Equatable, Sendable {
        /// Seuil du compresseur, dBFS.
        public var seuil: Float = -24
        public var ratio: Float = 5
        public var genou: Float = 6
        public var attaque: Float = 2      // ms
        public var relache: Float = 150    // ms
        /// Le plafond dur du limiteur, dBFS.
        public var plafond: Float = -12
        public var nivelleur = true
        /// Niveau efficace visé par le nivelleur, dBFS.
        public var cible: Float = -32
        public init() {}
    }

    /// Anticipation du limiteur : c'est la seule latence que le traitement ajoute.
    public static let anticipation: Float = 2   // ms

    // Réglage courant (écrit par le fil principal).
    private var r = Reglage()
    private var sr: Float = 48000
    private var attC: Float = 0, relC: Float = 0
    private var limAtt: Float = 0, limRel: Float = 0
    private var levC: Float = 0

    // État du traitement (fil temps réel seulement).
    private var ringL = [Float](repeating: 0, count: 1024)
    private var ringR = [Float](repeating: 0, count: 1024)
    private var pos = 0
    private var retard = 96
    private var levMs: Float = 0
    private var levDb: Float = 0
    private var levLin: Float = 1
    private var levTick = 0
    private var gr: Float = 0        // réduction du compresseur, dB (≥ 0)
    private var lim: Float = 1

    // Mesures (écrites ici, lues par l'interface).
    public private(set) var crêteEntree: Float = 0
    public private(set) var crêteSortie: Float = 0
    public private(set) var reductionMax: Float = 0
    public private(set) var appels: Int = 0
    public private(set) var echantillonsNonNuls: Int = 0
    public private(set) var latenceMs: Double = 0

    public init() { configurer(sampleRate: 48000, reglage: Reglage()) }

    public func configurer(sampleRate: Double, reglage: Reglage) {
        r = reglage
        sr = Float(max(8000, sampleRate))
        func coef(_ ms: Float) -> Float { exp(-1 / max(1, ms * 0.001 * sr)) }
        attC = coef(reglage.attaque)
        relC = coef(reglage.relache)
        limAtt = coef(0.4)
        limRel = coef(80)
        levC = coef(400)
        retard = min(ringL.count - 1, max(1, Int(Self.anticipation * 0.001 * sr)))
    }

    public func appliquer(_ reglage: Reglage) {
        configurer(sampleRate: Double(sr), reglage: reglage)
    }

    public func remettreMesures() {
        crêteEntree = 0; crêteSortie = 0; reductionMax = 0
    }

    func noterAppel(latenceMs l: Double) {
        appels &+= 1
        latenceMs = latenceMs == 0 ? l : latenceMs * 0.95 + l * 0.05
    }

    /// Traite `n` images. `entree`/`sortie` : pointeurs de départ des deux
    /// canaux, avec leur pas (2 pour de l'entrelacé, 1 pour du séparé).
    @inline(__always)
    func traiter(n: Int,
                 entreeL: UnsafePointer<Float>, entreeR: UnsafePointer<Float>, pasEntree: Int,
                 sortieL: UnsafeMutablePointer<Float>, sortieR: UnsafeMutablePointer<Float>, pasSortie: Int) {
        let seuil = r.seuil, ratio = max(1, r.ratio), genou = max(0.01, r.genou)
        let plafondLin = powf(10, r.plafond / 20)
        var pIn: Float = 0, pOut: Float = 0, grMax: Float = 0
        var nonNuls = 0
        let mask = ringL.count - 1   // 1024 = 2^10

        ringL.withUnsafeMutableBufferPointer { rl in
        ringR.withUnsafeMutableBufferPointer { rr in
        for i in 0..<n {
            var l = entreeL[i * pasEntree], rg = entreeR[i * pasEntree]
            if !l.isFinite { l = 0 }
            if !rg.isFinite { rg = 0 }
            let a = max(abs(l), abs(rg))
            if a > pIn { pIn = a }
            if a > 0 { nonNuls += 1 }

            // 1. Nivelleur : mesure lente de l'énergie, gain mis à jour toutes les 32 images.
            levMs += (a * a - levMs) * (1 - levC)
            levTick += 1
            if levTick >= 32 {
                levTick = 0
                var cibleGain: Float = 0
                if r.nivelleur {
                    let lv = 10 * log10f(levMs + 1e-12)
                    if lv > -55 {
                        cibleGain = min(6, max(-9, r.cible - lv))
                    } else {
                        cibleGain = levDb      // silence : on garde le gain, on ne remonte pas le bruit
                    }
                }
                // Baisse rapide (~0,5 s), remontée lente (~4 s).
                let tau: Float = cibleGain < levDb ? 1.2 : 3
                levDb += (cibleGain - levDb) * (1 - expf(-32 / (tau * sr)))
                levLin = powf(10, levDb / 20)
            }
            let x = a * levLin

            // 2. Compresseur à genou doux, détection sur le signal non retardé.
            let xDb = 20 * log10f(max(x, 1e-9))
            let over = xDb - seuil
            var reduc: Float = 0
            if 2 * over > genou {
                reduc = over - over / ratio
            } else if 2 * over > -genou {
                let t = over + genou / 2
                reduc = (1 - 1 / ratio) * t * t / (2 * genou)
            }
            gr = reduc > gr ? attC * gr + (1 - attC) * reduc : relC * gr + (1 - relC) * reduc
            if gr > grMax { grMax = gr }
            let g = levLin * powf(10, -gr / 20)

            // 3. Limiteur : il voit `retard` images dans le futur.
            let pic = a * g
            let besoin: Float = pic > plafondLin ? plafondLin / pic : 1
            lim = besoin < lim ? besoin + (lim - besoin) * limAtt : 1 + (lim - 1) * limRel

            // Ligne à retard.
            rl[pos & mask] = l
            rr[pos & mask] = rg
            let idx = (pos - retard) & mask
            let sl = rl[idx] * g * lim, sr2 = rr[idx] * g * lim
            pos = (pos + 1) & mask

            let ol = min(plafondLin, max(-plafondLin, sl))
            let or = min(plafondLin, max(-plafondLin, sr2))
            sortieL[i * pasSortie] = ol
            sortieR[i * pasSortie] = or
            let m = max(abs(ol), abs(or))
            if m > pOut { pOut = m }
        }}}
        if pIn > crêteEntree { crêteEntree = pIn }
        if pOut > crêteSortie { crêteSortie = pOut }
        if grMax > reductionMax { reductionMax = grMax }
        echantillonsNonNuls &+= nonNuls
    }

    /// Version tableau, pour le banc d'essai hors ligne.
    public func traiterHorsLigne(_ entree: [Float]) -> [Float] {
        var sortie = [Float](repeating: 0, count: entree.count)
        entree.withUnsafeBufferPointer { i in
            sortie.withUnsafeMutableBufferPointer { o in
                traiter(n: i.count, entreeL: i.baseAddress!, entreeR: i.baseAddress!, pasEntree: 1,
                        sortieL: o.baseAddress!, sortieR: o.baseAddress!, pasSortie: 1)
            }
        }
        return sortie
    }
}
