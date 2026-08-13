import AppKit
import Foundation

/// Runtime information about the mounted filesystem that owns a configured
/// FIND950 library folder. This intentionally stays outside the cached Akai
/// catalogue because mount state can change at any time.
struct FindMediaVolume: Identifiable, Equatable, Sendable {
    let mountURL: URL
    let name: String
    let isRemovable: Bool
    let isEjectable: Bool
    let isInternal: Bool?
    let isAvailable: Bool

    var id: String { mountURL.standardizedFileURL.path }

    var kindTitle: String {
        if !isAvailable { return "OFFLINE" }
        if isRemovable { return "REMOVABLE" }
        if isInternal == false { return "EXTERNAL" }
        if isEjectable { return "EJECTABLE" }
        return "MEDIA"
    }

    var statusTitle: String { "\(kindTitle) · \(name)" }

    func withAvailability(_ available: Bool) -> FindMediaVolume {
        FindMediaVolume(
            mountURL: mountURL,
            name: name,
            isRemovable: isRemovable,
            isEjectable: isEjectable,
            isInternal: isInternal,
            isAvailable: available
        )
    }
}

enum FindMediaVolumeResolver {
    private static let volumeKeys: Set<URLResourceKey> = [
        .volumeURLKey,
        .volumeNameKey,
        .volumeIsRemovableKey,
        .volumeIsEjectableKey,
        .volumeIsInternalKey,
        .volumeIsRootFileSystemKey
    ]

    static func mountedVolume(containing url: URL) -> FindMediaVolume? {
        var probe = url.standardizedFileURL
        while probe.path != "/",
              !FileManager.default.fileExists(atPath: probe.path) {
            probe.deleteLastPathComponent()
        }
        guard let values = try? probe.resourceValues(forKeys: volumeKeys),
              let mountURL = values.volume?.standardizedFileURL,
              values.volumeIsRootFileSystem != true
        else { return nil }

        let isRemovable = values.volumeIsRemovable == true
        let isEjectable = values.volumeIsEjectable == true
        let isInternal = values.volumeIsInternal
        guard isRemovable || isEjectable || isInternal == false else { return nil }

        return FindMediaVolume(
            mountURL: mountURL,
            name: values.volumeName ?? mountURL.lastPathComponent,
            isRemovable: isRemovable,
            isEjectable: isEjectable,
            isInternal: isInternal,
            isAvailable: true
        )
    }

    /// When a configured `/Volumes/<name>/…` path is absent at launch there is
    /// no resource metadata to query. Keep it visibly offline without guessing
    /// that it is ejectable (network shares also live below `/Volumes`).
    static func offlineVolumeHint(containing url: URL) -> FindMediaVolume? {
        let components = url.standardizedFileURL.pathComponents
        guard components.count >= 3,
              components[0] == "/",
              components[1] == "Volumes"
        else { return nil }
        let mountURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
            .appendingPathComponent(components[2], isDirectory: true)
        return FindMediaVolume(
            mountURL: mountURL,
            name: components[2],
            isRemovable: false,
            isEjectable: false,
            isInternal: nil,
            isAvailable: false
        )
    }
}
