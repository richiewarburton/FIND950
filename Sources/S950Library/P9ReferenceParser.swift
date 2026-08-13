import Foundation

public enum P9ReferenceParser {
    public static func sampleNames(in data: Data) throws -> [String] {
        let headerSize = 0x26
        let recordSize = 0x46
        guard data.count >= headerSize else {
            throw S950LibraryError.transferVerificationFailed("P9 is shorter than its header.")
        }
        let keygroupCount = Int(data[0x17])
        guard keygroupCount > 0, keygroupCount <= 99,
              data.count == headerSize + keygroupCount * recordSize
        else { throw S950LibraryError.transferVerificationFailed("P9 keygroup layout is invalid.") }

        var names: [String] = []
        for index in 0..<keygroupCount {
            let offset = headerSize + index * recordSize
            let soft = try decodeName(data.subdata(in: offset + 0x18..<offset + 0x22))
            let loud = try decodeName(data.subdata(in: offset + 0x2e..<offset + 0x38))
            if !soft.isEmpty, !names.contains(where: { normalized($0) == normalized(soft) }) {
                names.append(soft)
            }
            if !loud.isEmpty,
               normalized(loud) != "2 SAMPLE",
               !names.contains(where: { normalized($0) == normalized(loud) }) {
                names.append(loud)
            }
        }
        return names
    }

    public static func normalized(_ name: String) -> String {
        name.uppercased()
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// The filename identity used by the S950 directory. Native tools may
    /// render the same ten-character name with spaces or underscores.
    public static func nativeFilenameKey(_ filename: String) -> String {
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension.uppercased()
        return "\(normalized(stem)).\(ext)"
    }

    private static func decodeName(_ data: Data) throws -> String {
        var characters: [UInt8] = []
        for byte in data {
            if byte == 0 {
                characters.append(0x20)
            } else if byte >= 0x20, byte <= 0x7e {
                characters.append(byte)
            } else {
                throw S950LibraryError.transferVerificationFailed("P9 contains an invalid sample name.")
            }
        }
        return String(decoding: characters, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
    }
}
