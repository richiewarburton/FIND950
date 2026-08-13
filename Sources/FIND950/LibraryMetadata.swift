import AppKit
import Foundation
import SwiftUI

enum LibraryMetadataPersistence {
    static let locationDefaultsKey = "FIND950.libraryDataDirectory"
    private static let legacyBundleIdentifier = "com.e45recordings.S950LibraryBrowser"
    private static let legacyLocationDefaultsKey = "S950LibraryBrowser.libraryDataDirectory"

    static var directoryURL: URL {
        if let path = UserDefaults.standard.string(forKey: locationDefaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        if let path = UserDefaults(suiteName: legacyBundleIdentifier)?
            .string(forKey: legacyLocationDefaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        }
        return defaultDirectoryURL
    }

    static var defaultDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let preferred = base.appendingPathComponent("FIND950", isDirectory: true)
        let legacy = base.appendingPathComponent("S950 Library Browser", isDirectory: true)
        if !FileManager.default.fileExists(atPath: preferred.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }
        return preferred
    }

    static func indexFileURL(in folder: URL = directoryURL) -> URL {
        folder.appendingPathComponent("image-index-v1.json", isDirectory: false)
    }

    static func legacyMetadataFileURL(in folder: URL = directoryURL) -> URL {
        folder.appendingPathComponent("metadata.json", isDirectory: false)
    }
}

extension Color {
    init(s950Hex: String) {
        let clean = s950Hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(clean, radix: 16) ?? 0x6E7581
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    var s950Hex: String {
        let color = NSColor(self).usingColorSpace(.sRGB)
            ?? NSColor(srgbRed: 0.43, green: 0.46, blue: 0.51, alpha: 1)
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}
