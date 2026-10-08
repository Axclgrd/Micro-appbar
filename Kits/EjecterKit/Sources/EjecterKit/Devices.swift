import Commun
import Foundation

/// Un volume, monté ou non.
struct VolumeInfo: Identifiable, Sendable, Hashable {
    let id: String            // identifiant BSD, ex « disk7s1 »
    let name: String
    let mountPoint: String?
    let size: Int64
    let free: Int64?

    var isMounted: Bool { mountPoint != nil }
    var used: Int64? { free.map { size - $0 } }
}

/// Ce qu'on éjecte réellement : un disque, pas un volume.
///
/// Le piège du sujet est là. Sur un disque APFS externe, `/Volumes/X` est un
/// volume (`disk7s1`) d'un conteneur synthétisé (`disk7`) posé sur une
/// partition (`disk6s2`) du disque physique (`disk6`). Démonter `disk7s1` ne
/// coupe rien : c'est `disk6` qu'il faut éjecter pour pouvoir débrancher.
struct Device: Identifiable, Sendable, Hashable {

    enum Kind: Sendable, Hashable {
        case drive   // disque physique branché
        case image   // image disque montée (.dmg)
    }

    let id: String            // disque entier, ex « disk6 »
    let name: String
    let model: String
    let kind: Kind
    let size: Int64
    let volumes: [VolumeInfo]

    var mountedVolumes: [VolumeInfo] { volumes.filter(\.isMounted) }
    var isMounted: Bool { !mountedVolumes.isEmpty }

    /// Branché mais démonté : l'état que macOS n'offre aucun moyen de défaire
    /// sans débrancher puis rebrancher le câble.
    var isDormant: Bool { kind == .drive && !isMounted }

    var free: Int64? { mountedVolumes.compactMap(\.free).max() }
    var capacity: Int64 { mountedVolumes.map(\.size).max() ?? size }
    var fill: Double {
        guard let free, capacity > 0 else { return 0 }
        return min(max(Double(capacity - free) / Double(capacity), 0), 1)
    }
}

/// Relevé de l'état des disques externes.
///
/// Tout passe par `diskutil -plist` plutôt que par DiskArbitration : c'est la
/// seule source qui voie aussi les disques *branchés mais démontés*, ceux que
/// l'utilitaire de disque montre et que le Finder ignore.
actor DeviceScanner {

    func scan() -> [Device] {
        // Les disques physiques d'abord : tout le reste (cryptex du simulateur,
        // images de Xcode, .dmg d'installeurs) est virtuel et se traite à part.
        let physicalIDs: Set<String> = {
            guard let root = plist(["list", "-plist", "external", "physical"]),
                  let whole = root["WholeDisks"] as? [String] else { return [] }
            return Set(whole)
        }()

        guard let topology = plist(["list", "-plist", "external"]),
              let entries = topology["AllDisksAndPartitions"] as? [[String: Any]]
        else { return [] }

        // Conteneurs APFS indexés par leur magasin physique : c'est ce qui
        // permet de rattacher un volume au disque qu'on va éjecter.
        var containersByStore: [String: [String: Any]] = [:]
        for entry in entries where entry["Content"] as? String == "Apple_APFS_Container" {
            for store in entry["APFSPhysicalStores"] as? [[String: Any]] ?? [] {
                if let storeID = store["DeviceIdentifier"] as? String {
                    containersByStore[storeID] = entry
                }
            }
        }

        var devices: [Device] = []

        for entry in entries {
            guard entry["Content"] as? String != "Apple_APFS_Container",
                  let diskID = entry["DeviceIdentifier"] as? String
            else { continue }

            var volumes: [VolumeInfo] = []
            // Disque formaté d'un seul tenant : clé USB en exFAT, carte SD…
            if let solo = volume(from: entry) { volumes.append(solo) }

            for partition in entry["Partitions"] as? [[String: Any]] ?? [] {
                let partitionID = partition["DeviceIdentifier"] as? String ?? ""
                if let container = containersByStore[partitionID] {
                    for apfs in container["APFSVolumes"] as? [[String: Any]] ?? [] {
                        if let v = volume(from: apfs) { volumes.append(v) }
                    }
                } else if let v = volume(from: partition) {
                    volumes.append(v)
                }
            }

            let kind: Device.Kind = physicalIDs.contains(diskID) ? .drive : .image

            // Les volumes système montés hors de /Volumes (bundles du
            // simulateur, cryptex) sont des images disque qui ne regardent pas
            // l'utilisateur : on ne garde une image que si elle apparaît là où
            // le Finder la montrerait.
            if kind == .image {
                volumes = volumes.filter { ($0.mountPoint ?? "").hasPrefix("/Volumes/") }
                guard !volumes.isEmpty else { continue }
            }
            guard !volumes.isEmpty else { continue }

            let info = kind == .drive ? plist(["info", "-plist", diskID]) : nil
            let model = (info?["MediaName"] as? String)?
                .trimmingCharacters(in: .whitespaces) ?? "Image disque"

            // Un seul volume : son nom est ce que l'utilisateur reconnaît.
            // Plusieurs : le nom du matériel est le seul qui les englobe.
            let name = volumes.count == 1 ? volumes[0].name : model

            devices.append(Device(
                id: diskID,
                name: name,
                model: model,
                kind: kind,
                size: (entry["Size"] as? NSNumber)?.int64Value ?? 0,
                volumes: volumes
            ))
        }

        // Les disques branchés d'abord, les images ensuite : on range par
        // importance, pas par ordre d'apparition dans /dev.
        return devices.sorted { lhs, rhs in
            lhs.kind == rhs.kind ? lhs.name < rhs.name : lhs.kind == .drive
        }
    }

    // MARK: Détail

    private func volume(from dict: [String: Any]) -> VolumeInfo? {
        guard let id = dict["DeviceIdentifier"] as? String,
              let name = dict["VolumeName"] as? String, !name.isEmpty,
              dict["Content"] as? String != "EFI"
        else { return nil }

        let mountPoint = (dict["MountPoint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var size = (dict["Size"] as? NSNumber)?.int64Value ?? 0
        var free: Int64?

        // Monté, on demande au système : la taille de la partition n'est pas
        // l'espace utilisable, et « Size » d'un volume APFS est celle du
        // conteneur entier, partagée avec ses voisins.
        if let mountPoint {
            let url = URL(fileURLWithPath: mountPoint)
            if let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
            ]) {
                if let total = values.volumeTotalCapacity { size = Int64(total) }
                free = values.volumeAvailableCapacityForImportantUsage
            }
        }

        return VolumeInfo(id: id, name: name, mountPoint: mountPoint, size: size, free: free)
    }

    private func plist(_ arguments: [String]) -> [String: Any]? {
        let result = Shell.run(Shell.diskutil, arguments)
        guard result.ok, !result.out.isEmpty else { return nil }
        return (try? PropertyListSerialization.propertyList(
            from: result.out, options: [], format: nil)) as? [String: Any]
    }
}
