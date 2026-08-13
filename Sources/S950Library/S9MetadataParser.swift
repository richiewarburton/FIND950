import Foundation

enum S9MetadataParser {
    private static let sampleRateOffset = 0x14

    static func sampleRate(in data: Data) -> Int? {
        guard data.count >= sampleRateOffset + 2 else { return nil }
        let rate = data.withUnsafeBytes { bytes -> UInt16 in
            let low = UInt16(bytes[sampleRateOffset])
            let high = UInt16(bytes[sampleRateOffset + 1]) << 8
            return low | high
        }
        return rate == 0 ? nil : Int(rate)
    }
}
