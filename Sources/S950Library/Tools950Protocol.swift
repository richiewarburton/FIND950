import CryptoKit
import Foundation

public enum Tools950Protocol {
    // Protocol-v1 wire identifiers remain unchanged so existing suite builds
    // continue to exchange request documents during the product-name migration.
    public static let protocolIdentifier = "com.e45recordings.akai-tools"
    public static let protocolVersion = 1
    public static let requestExtension = "akaitoolsrequest"
    public static let requestUTI = "com.e45recordings.akai-tools.request"
    public static let maximumDocumentBytes = 65_536
    public static let maximumDependencyCount = 128
    public static let defaultLifetime: TimeInterval = 30 * 60
    public static let acknowledgementTimeout: TimeInterval = 10

    public struct Sender: Codable, Equatable, Sendable {
        public let productID: String
        public let version: String
        public let build: String?

        public init(productID: String, version: String, build: String? = nil) {
            self.productID = productID
            self.version = version
            self.build = build
        }
    }

    public struct ResponseTransport: Codable, Equatable, Sendable {
        public let path: String
        public let expiresAt: Date
    }

    public struct Source: Codable, Equatable, Sendable {
        public let path: String
        public let sha256: String
        public let byteSize: UInt64?
        public let modifiedAt: Date?
    }

    public struct NativeProgram: Codable, Equatable, Sendable {
        public let volumePath: String
        public let directoryIndex: Int
        public let filename: String
        public let internalName: String?
    }

    public struct Dependency: Codable, Equatable, Sendable {
        public let directoryIndex: Int?
        public let filename: String
        public let internalName: String?
    }

    public struct ExportProgramRequest: Codable, Equatable, Sendable {
        public let protocolIdentifier: String
        public let protocolVersion: Int
        public let messageType: String
        public let requestID: UUID
        public let createdAt: Date
        public let sender: Sender
        public let response: ResponseTransport
        public let source: Source
        public let program: NativeProgram
        public let observedDependencies: [Dependency]
        public let openInPLAY950AfterExport: Bool
        public let exportMode: String?

        enum CodingKeys: String, CodingKey {
            case protocolIdentifier = "protocol"
            case protocolVersion
            case messageType
            case requestID
            case createdAt
            case sender
            case response
            case source
            case program
            case observedDependencies
            case openInPLAY950AfterExport = "openInTRUE950AfterExport"
            case exportMode
        }
    }

    public struct CollectionItem: Codable, Equatable, Sendable {
        public let sourceIndex: Int
        public let volumePath: String
        public let directoryIndex: Int
        public let filename: String
        public let kind: String
    }

    public struct ExportCollectionRequest: Codable, Equatable, Sendable {
        public let protocolIdentifier: String
        public let protocolVersion: Int
        public let messageType: String
        public let requestID: UUID
        public let createdAt: Date
        public let sender: Sender
        public let response: ResponseTransport
        public let sources: [Source]
        public let items: [CollectionItem]

        enum CodingKeys: String, CodingKey {
            case protocolIdentifier = "protocol"
            case protocolVersion
            case messageType
            case requestID
            case createdAt
            case sender
            case response
            case sources
            case items
        }
    }

    public struct ExportVerification: Codable, Equatable, Sendable {
        public let sourceSHA256: String
        public let destinationSHA256: String
        public let sourceUnchanged: Bool
        public let exactDirectoryVerified: Bool
        public let nativeBytesVerified: Bool
        public let backupVerified: Bool
        public let rollbackPerformed: Bool
        public let sourceByteSize: UInt64
        public let destinationByteSize: UInt64
        public let importedFileCount: Int
    }

    public struct ExportProgramResult: Codable, Equatable, Sendable {
        public let resultingImage: Source
        public let resolvedVolumePath: String
        public let program: NativeProgram
        public let dependencies: [Dependency]
        public let backupPath: String?
        public let verification: ExportVerification
        public let warnings: [String]
    }

    public enum ResponseStatus: String, Codable, Sendable {
        case accepted
        case completed
        case failed
        case rejected

        public var isTerminal: Bool { self != .accepted }
    }

    public struct OperationResponse: Codable, Equatable, Sendable {
        public let protocolIdentifier: String
        public let protocolVersion: Int
        public let messageType: String
        public let requestID: UUID
        public let createdAt: Date
        public let sender: Sender
        public let status: ResponseStatus
        public let operationType: String
        public let summary: String?
        public let errorCode: String?
        public let details: [String: String]?
        public let result: ExportProgramResult?

        enum CodingKeys: String, CodingKey {
            case protocolIdentifier = "protocol"
            case protocolVersion
            case messageType
            case requestID
            case createdAt
            case sender
            case status
            case operationType
            case summary
            case errorCode
            case details
            case result
        }
    }

    public struct PreparedHandoff: Equatable, Sendable {
        public let request: ExportProgramRequest
        public let requestURL: URL
        public let responseURL: URL
        public let artifactDirectory: URL

        public func cleanup(fileManager: FileManager = .default) {
            try? fileManager.removeItem(at: artifactDirectory)
        }
    }

    public struct PreparedCollectionHandoff: Equatable, Sendable {
        public let request: ExportCollectionRequest
        public let requestURL: URL
        public let responseURL: URL
        public let artifactDirectory: URL

        public func cleanup(fileManager: FileManager = .default) {
            try? fileManager.removeItem(at: artifactDirectory)
        }
    }

    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func deterministicRequestID(
        sourcePath: String,
        sourceSHA256: String,
        volumePath: String,
        directoryIndex: Int,
        filename: String,
        createdAt: Date,
        exportMode: String = "image"
    ) -> UUID {
        let material = [
            sourcePath,
            sourceSHA256,
            volumePath,
            String(directoryIndex),
            filename,
            exportMode,
            String(format: "%.6f", createdAt.timeIntervalSince1970)
        ].joined(separator: "\u{1f}")
        var bytes = Array(SHA256.hash(data: Data(material.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let text = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
        return UUID(uuidString: text)!
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
