import Foundation
import SMCKit

// fancontrold — démon privilégié.
//
// Tourne en root parce que le firmware SMC réserve l'écriture à root. Il ne
// fait rien d'autre : toute l'interface est dans l'app non privilégiée, qui
// lui parle par un socket Unix.
//
// Règle de sûreté centrale : le mode manuel est adossé à la *durée de vie de
// la connexion*. Si l'app se ferme, plante, ou est tuée, le noyau ferme le
// socket et le démon repasse en automatique. Il n'existe aucun chemin où les
// ventilateurs restent bloqués parce que le client a disparu.

// MARK: - Options

var socketPath = FanProtocol.socketPath
var ownerUID: uid_t = 0

var argIterator = CommandLine.arguments.dropFirst().makeIterator()
while let arg = argIterator.next() {
    switch arg {
    case "--socket": if let v = argIterator.next() { socketPath = v }
    case "--owner":  if let v = argIterator.next(), let n = UInt32(v) { ownerUID = n }
    default: break
    }
}

func log(_ message: String) {
    FileHandle.standardError.write(Data("[fancontrold] \(message)\n".utf8))
}

guard getuid() == 0 else {
    log("doit tourner en root")
    exit(1)
}

// MARK: - Accès matériel

let smc: SMC
let fans: FanController
let sensors: ThermalSensors
do {
    smc = try SMC()
    fans = try FanController(smc: smc)
    sensors = ThermalSensors(smc: smc)
} catch {
    log("initialisation SMC impossible : \(error)")
    exit(1)
}

let fanRange = fans.range()
log("démarré — \(fans.count) ventilateurs, plage \(Int(fanRange.lowerBound))–\(Int(fanRange.upperBound)) RPM")

// MARK: - État partagé

final class State: @unchecked Sendable {
    private let lock = NSLock()
    /// Consigne demandée par l'utilisateur. `nil` = automatique.
    private var _requested: Double?
    private var _safetyOverride = false

    var requested: Double? {
        get { lock.lock(); defer { lock.unlock() }; return _requested }
        set { lock.lock(); _requested = newValue; lock.unlock() }
    }
    var safetyOverride: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _safetyOverride }
        set { lock.lock(); _safetyOverride = newValue; lock.unlock() }
    }
}

let state = State()

/// Plancher de vitesse imposé quelle que soit la demande de l'utilisateur.
///
/// Sans ça, laisser le curseur au minimum pendant une compilation ou un jeu
/// ferait monter le SoC bien plus haut que ne l'aurait permis la courbe
/// d'Apple : on aurait remplacé une machine trop chaude par une machine
/// dangereusement chaude. Le curseur ne peut donc que *refroidir davantage*
/// que le système, jamais moins, une fois la zone critique atteinte.
@Sendable func safetyFloor() -> Double {
    guard let hotspot = sensors.read().hotspot else { return fanRange.lowerBound }
    let span = fanRange.upperBound - fanRange.lowerBound
    switch hotspot {
    case 95...:  return fanRange.lowerBound + span * 0.85
    case 88..<95: return fanRange.lowerBound + span * 0.60
    default:     return fanRange.lowerBound
    }
}

/// Applique la consigne courante. Ré-affirmée périodiquement : `thermalmonitord`
/// peut reprendre la main, notamment au réveil après une mise en veille.
@Sendable func applyCurrentSetting() {
    guard let requested = state.requested else { return }
    let floor = safetyFloor()
    let effective = max(requested, floor)
    state.safetyOverride = effective > requested + 1
    do {
        try fans.setSpeedAll(effective)
    } catch {
        log("application de la consigne impossible : \(error)")
    }
}

func returnToAutomatic(reason: String) {
    guard state.requested != nil else { return }
    state.requested = nil
    state.safetyOverride = false
    let ok = fans.restoreAutomaticVerified()
    log("retour en automatique (\(reason)) — \(ok ? "confirmé" : "ÉCHEC")")
}

// MARK: - Arrêt propre

func shutdown(_ reason: String) -> Never {
    state.requested = nil
    fans.restoreAutomaticVerified()
    unlink(socketPath)
    log("arrêt (\(reason)) — ventilateurs en automatique")
    exit(0)
}

// Les sources doivent survivre à la portée de la boucle, sinon elles sont
// désallouées et les signaux ne sont plus captés.
var signalSources: [DispatchSourceSignal] = []

for sig in [SIGINT, SIGTERM, SIGHUP] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    source.setEventHandler { shutdown("signal \(sig)") }
    source.resume()
    // Conservé en vie par la boucle d'exécution du démon.
    signalSources.append(source)
}

// MARK: - Ré-affirmation périodique

let reassertThread = Thread {
    while true {
        Thread.sleep(forTimeInterval: 2.0)
        applyCurrentSetting()
    }
}
reassertThread.start()

// MARK: - Socket

unlink(socketPath)

let listener = socket(AF_UNIX, SOCK_STREAM, 0)
guard listener >= 0 else { log("socket() a échoué"); exit(1) }

var address = FanProtocol.address(for: socketPath)
let bindResult = withUnsafePointer(to: &address) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
        bind(listener, sa, FanProtocol.addressLength)
    }
}
guard bindResult == 0 else { log("bind() a échoué sur \(socketPath)"); exit(1) }

// Le socket appartient à l'utilisateur de session, en 0600 : seul son compte
// peut piloter les ventilateurs, pas n'importe quel processus local.
chown(socketPath, ownerUID, 0)
chmod(socketPath, 0o600)

guard listen(listener, 4) == 0 else { log("listen() a échoué"); exit(1) }
log("à l'écoute sur \(socketPath) (propriétaire uid=\(ownerUID))")

// MARK: - Boucle de service

func snapshot() -> FanReply {
    let states = fans.allStates()
    return FanReply(
        ok: true,
        fans: states.map {
            FanReply.Fan(index: $0.index, actual: $0.actual,
                         target: $0.target, manual: $0.mode.isManual)
        },
        minimumRPM: fanRange.lowerBound,
        maximumRPM: fanRange.upperBound,
        requestedRPM: state.requested,
        safetyOverride: state.safetyOverride
    )
}

let encoder = JSONEncoder()
let decoder = JSONDecoder()

while true {
    let client = accept(listener, nil, nil)
    if client < 0 { continue }
    log("client connecté")

    var buffer = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)

    readLoop: while true {
        let n = read(client, &chunk, chunk.count)
        // n == 0 : le client a fermé (y compris en plantant). C'est le filet
        // de sécurité principal.
        guard n > 0 else { break readLoop }
        buffer.append(contentsOf: chunk[0..<n])

        while let newline = buffer.firstIndex(of: 0x0a) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]

            guard let request = try? decoder.decode(FanRequest.self, from: Data(line)) else {
                continue
            }
            switch request.command {
            case .status:
                break
            case .manual:
                if let rpm = request.rpm {
                    state.requested = rpm.clamped(to: fanRange)
                    applyCurrentSetting()
                    log("mode manuel : \(Int(rpm)) RPM")
                }
            case .auto:
                returnToAutomatic(reason: "demande utilisateur")
            }

            if let data = try? encoder.encode(snapshot()) {
                var payload = data
                payload.append(0x0a)
                _ = payload.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
            }
        }
    }

    close(client)
    returnToAutomatic(reason: "client déconnecté")
}
