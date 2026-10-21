import CoreAudio
import Foundation

/// Ce que le système dit de l'entrée audio par défaut.
struct EtatMicro: Equatable {
    var actif: Bool
    var bluetooth: Bool
    var nom: String
}

/// Surveille l'entrée audio par défaut, sans jamais l'ouvrir.
///
/// `kAudioDevicePropertyDeviceIsRunningSomewhere` répond « quelqu'un, quelque
/// part, capture sur ce périphérique ». C'est une lecture de propriété : elle
/// ne passe pas par l'autorisation Micro et n'allume pas l'indicateur orange.
/// Deux écouteurs, pas de sondage : l'un sur le changement d'entrée par défaut
/// (AirPods qui se connectent, qui s'éteignent), l'autre sur le périphérique
/// courant.
@MainActor
final class MicMonitor {
    private let onChange: (EtatMicro) -> Void
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var defaultListener: AudioObjectPropertyListenerBlock?
    private var runningListener: AudioObjectPropertyListenerBlock?
    private var started = false

    init(onChange: @escaping (EtatMicro) -> Void) {
        self.onChange = onChange
    }

    private static var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    private static var runningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard !started else { return }
        started = true

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reattach() }
        }
        defaultListener = block
        var address = Self.defaultInputAddress
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        reattach()
    }

    func stop() {
        guard started else { return }
        started = false
        detach()
        if let block = defaultListener {
            var address = Self.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        }
        defaultListener = nil
    }

    /// L'entrée par défaut a changé : l'écouteur de l'ancienne ne sert plus.
    private func reattach() {
        detach()
        device = Self.defaultInput()
        if device != kAudioObjectUnknown {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.report() }
            }
            runningListener = block
            var address = Self.runningAddress
            AudioObjectAddPropertyListenerBlock(device, &address, .main, block)
        }
        report()
    }

    private func detach() {
        if let block = runningListener, device != kAudioObjectUnknown {
            var address = Self.runningAddress
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        runningListener = nil
    }

    private func report() {
        onChange(Self.etat(of: device))
    }

    // MARK: Lectures CoreAudio

    static func defaultInput() -> AudioObjectID {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = defaultInputAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : AudioObjectID(kAudioObjectUnknown)
    }

    static func etat(of device: AudioObjectID) -> EtatMicro {
        guard device != kAudioObjectUnknown else {
            return EtatMicro(actif: false, bluetooth: false, nom: "Aucune entrée")
        }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = runningAddress
        let ok = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr

        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var transportAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(device, &transportAddress, 0, nil, &size, &transport)

        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let named = AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &size, &name) == noErr

        return EtatMicro(
            actif: ok && running != 0,
            bluetooth: transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE,
            nom: named ? (name?.takeRetainedValue() as String? ?? "Entrée") : "Entrée")
    }
}
