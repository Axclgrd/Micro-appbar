import Foundation
import IOKit

/// Client brut du System Management Controller.
///
/// Protocole : on ouvre le service IOKit `AppleSMC` et on échange une structure
/// de 80 octets via `IOConnectCallStructMethod` (sélecteur 2). On la manipule
/// comme un tampon d'octets avec des décalages explicites plutôt qu'en `struct`
/// Swift, pour ne pas dépendre des règles d'alignement du compilateur.
///
/// La lecture ne demande aucun privilège ; l'écriture exige root (c'est le
/// firmware SMC qui l'impose, par clé, pas IOKit).
public final class SMC: @unchecked Sendable {

    // MARK: Disposition de SMCKeyData_t (80 octets)

    private static let structSize = 80
    private enum Offset {
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let result = 40
        static let data8 = 42
        static let data32 = 44
        static let bytes = 48
    }

    private enum Command {
        static let readBytes: UInt8 = 5
        static let writeBytes: UInt8 = 6
        static let readIndex: UInt8 = 8
        static let readKeyInfo: UInt8 = 9
    }

    // MARK: Erreurs

    public enum SMCError: Error, CustomStringConvertible {
        case serviceUnavailable
        case notPrivileged
        case keyNotFound(String)
        case keyNotWritable(String)
        case rejectedByFirmware(String)
        case unexpected(key: String, ioReturn: Int32, smcResult: UInt8)

        public var description: String {
            switch self {
            case .serviceUnavailable:
                return "Service AppleSMC introuvable"
            case .notPrivileged:
                return "Privilèges insuffisants (root requis pour écrire)"
            case .keyNotFound(let k):
                return "Clé SMC inconnue : \(k)"
            case .keyNotWritable(let k):
                return "Clé SMC en lecture seule : \(k)"
            case .rejectedByFirmware(let k):
                return "Écriture de \(k) refusée par le firmware"
            case .unexpected(let k, let io, let smc):
                return String(format: "Échec SMC sur %@ (IOKit 0x%08x, SMC 0x%02x)",
                              k, UInt32(bitPattern: io), smc)
            }
        }
    }

    /// Codes de retour du firmware SMC (cf. SDK VirtualSMC).
    private enum SMCResult {
        static let success: UInt8 = 0
        static let badCommand: UInt8 = 0x82
        static let notFound: UInt8 = 0x84
        static let notWritable: UInt8 = 0x86
    }

    private static let ioReturnNotPrivileged = Int32(bitPattern: 0xe000_02c2)

    // MARK: État

    private var connection: io_connect_t = 0
    /// Le pilote SMC ne tolère pas les appels concurrents sur une même connexion.
    private let lock = NSLock()
    /// Les métadonnées d'une clé (taille, type) ne changent jamais : on les cache
    /// pour diviser par deux le nombre d'allers-retours IOKit sur le chemin chaud.
    private var keyInfoCache: [String: KeyInfo] = [:]

    public struct KeyInfo: Sendable {
        public let size: Int
        public let typeCode: UInt32
        public let type: String
    }

    // MARK: Cycle de vie

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceUnavailable }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            throw SMCError.serviceUnavailable
        }
        connection = conn
    }

    deinit {
        if connection != 0 { IOServiceClose(connection) }
    }

    // MARK: Primitives

    private func fourCharCode(_ key: String) -> UInt32 {
        var value: UInt32 = 0
        for byte in key.utf8.prefix(4) { value = (value << 8) | UInt32(byte) }
        return value
    }

    private func putLE32(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        buffer[offset]     = UInt8(value & 0xff)
        buffer[offset + 1] = UInt8((value >> 8) & 0xff)
        buffer[offset + 2] = UInt8((value >> 16) & 0xff)
        buffer[offset + 3] = UInt8((value >> 24) & 0xff)
    }

    private func getLE32(_ buffer: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(buffer[offset])
            | (UInt32(buffer[offset + 1]) << 8)
            | (UInt32(buffer[offset + 2]) << 16)
            | (UInt32(buffer[offset + 3]) << 24)
    }

    /// Un aller-retour IOKit. À appeler avec `lock` déjà tenu.
    private func callDriver(_ input: inout [UInt8]) -> (ioReturn: Int32, smcResult: UInt8, output: [UInt8]) {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outputSize = Self.structSize
        let ioReturn = input.withUnsafeBytes { inPtr in
            output.withUnsafeMutableBytes { outPtr in
                IOConnectCallStructMethod(connection, 2,
                                          inPtr.baseAddress!, Self.structSize,
                                          outPtr.baseAddress!, &outputSize)
            }
        }
        return (ioReturn, output[Offset.result], output)
    }

    private func translate(key: String, ioReturn: Int32, smcResult: UInt8) -> SMCError {
        if ioReturn == Self.ioReturnNotPrivileged { return .notPrivileged }
        switch smcResult {
        case SMCResult.notFound:    return .keyNotFound(key)
        case SMCResult.notWritable: return .keyNotWritable(key)
        case SMCResult.badCommand:  return .rejectedByFirmware(key)
        default: return .unexpected(key: key, ioReturn: ioReturn, smcResult: smcResult)
        }
    }

    // MARK: Métadonnées

    /// Taille et type d'une clé. Résultat mis en cache.
    public func info(for key: String) throws -> KeyInfo {
        lock.lock()
        defer { lock.unlock() }
        return try uncheckedInfo(for: key)
    }

    private func uncheckedInfo(for key: String) throws -> KeyInfo {
        if let cached = keyInfoCache[key] { return cached }

        var input = [UInt8](repeating: 0, count: Self.structSize)
        putLE32(&input, Offset.key, fourCharCode(key))
        input[Offset.data8] = Command.readKeyInfo

        let (ioReturn, smcResult, output) = callDriver(&input)
        guard ioReturn == kIOReturnSuccess, smcResult == SMCResult.success else {
            throw translate(key: key, ioReturn: ioReturn, smcResult: smcResult)
        }

        let typeCode = getLE32(output, Offset.dataType)
        let typeBytes = [UInt8(typeCode & 0xff), UInt8((typeCode >> 8) & 0xff),
                         UInt8((typeCode >> 16) & 0xff), UInt8((typeCode >> 24) & 0xff)]
        let info = KeyInfo(
            size: Int(getLE32(output, Offset.dataSize)),
            typeCode: typeCode,
            type: String(bytes: typeBytes.reversed(), encoding: .ascii) ?? "????"
        )
        keyInfoCache[key] = info
        return info
    }

    /// `true` si la clé existe sur cette machine.
    public func exists(_ key: String) -> Bool {
        (try? info(for: key)) != nil
    }

    // MARK: Lecture

    public func readBytes(_ key: String) throws -> [UInt8] {
        lock.lock()
        defer { lock.unlock() }

        let meta = try uncheckedInfo(for: key)
        guard meta.size > 0, meta.size <= 32 else { return [] }

        var input = [UInt8](repeating: 0, count: Self.structSize)
        putLE32(&input, Offset.key, fourCharCode(key))
        putLE32(&input, Offset.dataSize, UInt32(meta.size))
        putLE32(&input, Offset.dataType, meta.typeCode)
        input[Offset.data8] = Command.readBytes

        let (ioReturn, smcResult, output) = callDriver(&input)
        guard ioReturn == kIOReturnSuccess, smcResult == SMCResult.success else {
            throw translate(key: key, ioReturn: ioReturn, smcResult: smcResult)
        }
        return Array(output[Offset.bytes..<(Offset.bytes + meta.size)])
    }

    /// Lit une clé de type `flt ` (IEEE-754 petit-boutiste sur Apple Silicon).
    public func readFloat(_ key: String) throws -> Float {
        let bytes = try readBytes(key)
        guard bytes.count == 4 else { throw SMCError.keyNotFound(key) }
        return Float(bitPattern: getLE32(bytes, 0))
    }

    public func readUInt8(_ key: String) throws -> UInt8 {
        let bytes = try readBytes(key)
        guard let first = bytes.first else { throw SMCError.keyNotFound(key) }
        return first
    }

    // MARK: Écriture (root requis)

    public func writeBytes(_ key: String, _ payload: [UInt8]) throws {
        lock.lock()
        defer { lock.unlock() }

        let meta = try uncheckedInfo(for: key)

        var input = [UInt8](repeating: 0, count: Self.structSize)
        putLE32(&input, Offset.key, fourCharCode(key))
        putLE32(&input, Offset.dataSize, UInt32(meta.size))
        putLE32(&input, Offset.dataType, meta.typeCode)
        input[Offset.data8] = Command.writeBytes
        for (index, byte) in payload.prefix(meta.size).enumerated() {
            input[Offset.bytes + index] = byte
        }

        let (ioReturn, smcResult, _) = callDriver(&input)
        guard ioReturn == kIOReturnSuccess, smcResult == SMCResult.success else {
            throw translate(key: key, ioReturn: ioReturn, smcResult: smcResult)
        }
    }

    public func writeFloat(_ key: String, _ value: Float) throws {
        let bits = value.bitPattern
        try writeBytes(key, [UInt8(bits & 0xff), UInt8((bits >> 8) & 0xff),
                             UInt8((bits >> 16) & 0xff), UInt8((bits >> 24) & 0xff)])
    }

    public func writeUInt8(_ key: String, _ value: UInt8) throws {
        try writeBytes(key, [value])
    }

    // MARK: Énumération

    /// Nombre total de clés exposées par le SMC.
    public func keyCount() throws -> UInt32 {
        let bytes = try readBytes("#KEY")
        guard bytes.count == 4 else { return 0 }
        // `#KEY` est de type ui32, donc gros-boutiste dans la charge utile.
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
             | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    /// Nom de la clé à l'index donné, pour parcourir tout le SMC.
    public func key(at index: UInt32) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        var input = [UInt8](repeating: 0, count: Self.structSize)
        input[Offset.data8] = Command.readIndex
        putLE32(&input, Offset.data32, index)

        let (ioReturn, smcResult, output) = callDriver(&input)
        guard ioReturn == kIOReturnSuccess, smcResult == SMCResult.success else {
            throw translate(key: "index \(index)", ioReturn: ioReturn, smcResult: smcResult)
        }
        let code = getLE32(output, Offset.key)
        let bytes = [UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
                     UInt8((code >> 8) & 0xff), UInt8(code & 0xff)]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}
