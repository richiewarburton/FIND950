import Foundation

public enum S950EntryKind: String, Codable, Sendable {
    case program
    case sample
    case effects
    case drumSet
    case cueList
    case multi
    case unknown
    case other // legacy cached indexes decode without migration

    public var displayName: String {
        switch self {
        case .program: "PROGRAM"
        case .sample: "SAMPLE"
        case .effects: "EFFECTS"
        case .drumSet: "DRUM SET"
        case .cueList: "CUE LIST"
        case .multi: "MULTI"
        case .unknown, .other: "UNKNOWN"
        }
    }

    static func classify(filename: String) -> S950EntryKind {
        switch (filename as NSString).pathExtension.uppercased() {
        case "P", "P1", "P3", "P9": .program
        case "S", "S9": .sample
        case "O", "O9": .effects
        case "D", "D9": .drumSet
        case "C", "C9", "X": .cueList
        case "M", "M9": .multi
        default: .unknown
        }
    }
}

public struct S950LibraryEntry: Codable, Equatable, Identifiable, Sendable {
    public let index: Int
    public let name: String
    public let byteSize: Int64
    public let kind: S950EntryKind
    public let sampleReferences: [String]
    public let sampleRate: Int?

    public var id: String { "\(index)|\(name.uppercased())" }
    public var sampleRateSortValue: Int { sampleRate ?? -1 }

    public init(
        index: Int,
        name: String,
        byteSize: Int64,
        kind: S950EntryKind,
        sampleReferences: [String] = [],
        sampleRate: Int? = nil
    ) {
        self.index = index
        self.name = name
        self.byteSize = byteSize
        self.kind = kind
        self.sampleReferences = sampleReferences
        self.sampleRate = sampleRate
    }
}

public struct S950VolumeCatalog: Codable, Equatable, Identifiable, Sendable {
    public let name: String
    public let path: String
    public let entries: [S950LibraryEntry]

    public var id: String { path }
    public var programs: [S950LibraryEntry] { entries.filter { $0.kind == .program } }
    public var samples: [S950LibraryEntry] { entries.filter { $0.kind == .sample } }

    public init(name: String, path: String, entries: [S950LibraryEntry]) {
        self.name = name
        self.path = path
        self.entries = entries
    }
}

public struct S950ImageCatalog: Codable, Equatable, Identifiable, Sendable {
    public let imageURL: URL
    public let libraryFolderURL: URL?
    public let name: String
    public let volumes: [S950VolumeCatalog]

    public var id: URL { imageURL }
    public var programCount: Int { volumes.reduce(0) { $0 + $1.programs.count } }
    public var sampleCount: Int { volumes.reduce(0) { $0 + $1.samples.count } }

    public init(
        imageURL: URL,
        name: String,
        volumes: [S950VolumeCatalog],
        libraryFolderURL: URL? = nil
    ) {
        self.imageURL = imageURL
        self.libraryFolderURL = libraryFolderURL
        self.name = name
        self.volumes = volumes
    }
}

public struct S950ScanFailure: Codable, Equatable, Sendable {
    public let imageURL: URL
    public let message: String

    public init(imageURL: URL, message: String) {
        self.imageURL = imageURL
        self.message = message
    }
}

public struct S950LibraryScan: Codable, Equatable, Sendable {
    public let folderURL: URL
    public let images: [S950ImageCatalog]
    public let failures: [S950ScanFailure]

    public init(folderURL: URL, images: [S950ImageCatalog], failures: [S950ScanFailure]) {
        self.folderURL = folderURL
        self.images = images
        self.failures = failures
    }
}

public struct S950LibraryCollection: Codable, Equatable, Sendable {
    public let folderURLs: [URL]
    public let images: [S950ImageCatalog]
    public let failures: [S950ScanFailure]

    public init(folderURLs: [URL], images: [S950ImageCatalog], failures: [S950ScanFailure]) {
        self.folderURLs = folderURLs
        self.images = images
        self.failures = failures
    }
}

public enum S950LibraryError: LocalizedError {
    case folderNotFound(String)
    case helperNotFound
    case helperNotExecutable(String)
    case helperExited(String)
    case promptNotFound(String)
    case invalidSample
    case temporaryExportFailed(String)
    case invalidProgram
    case missingReferencedSamples([String])
    case destinationCollision([String])
    case transferVerificationFailed(String)
    case readOnlyCommandRequired(String)
    case edit950NotFound
    case acknowledgementTimeout
    case responseExpired
    case unsupportedProtocolVersion(Int)
    case invalidHandoff(String)
    case invalidImageForIndex(String)

    public var errorDescription: String? {
        switch self {
        case .folderNotFound(let path): return "The IMG folder does not exist: \(path)"
        case .helperNotFound:
            return "AKAI Util was not found for the command-line tool. Pass --akaiutil /path/to/akaiutil or set AKAIUTIL_PATH."
        case .helperNotExecutable(let path): return "AKAI Util is not executable: \(path)"
        case .helperExited(let detail): return "AKAI Util exited unexpectedly. \(detail)"
        case .promptNotFound(let detail): return "AKAI Util did not return a prompt. \(detail)"
        case .invalidSample: return "Only a valid S950 sample can be auditioned."
        case .temporaryExportFailed(let name): return "AKAI Util did not export a temporary WAV for \(name)."
        case .invalidProgram: return "Only a valid S950 program can be transferred."
        case .missingReferencedSamples(let names):
            return "The program references samples that are not present in its volume: \(names.joined(separator: ", "))."
        case .destinationCollision(let names):
            return "The destination already contains: \(names.joined(separator: ", ")). Choose another image."
        case .transferVerificationFailed(let detail): return "Program transfer verification failed: \(detail)"
        case .readOnlyCommandRequired(let verb):
            return "FIND950 blocked the non-read-only AKAI Util command '\(verb)'. IMG mutations must be handed to EDIT950."
        case .edit950NotFound:
            return "EDIT950 is required for IMG export. Install it in Applications or locate the app."
        case .acknowledgementTimeout:
            return "EDIT950 did not acknowledge the export request within 10 seconds. Check that the installed EDIT950 version supports 950TOOLS protocol v1."
        case .responseExpired:
            return "The EDIT950 export request expired before a terminal response arrived. No export is being claimed."
        case .unsupportedProtocolVersion(let version):
            return "950TOOLS protocol version \(version) is not supported by this FIND950."
        case .invalidHandoff(let detail):
            return "The EDIT950 handoff is invalid: \(detail)"
        case .invalidImageForIndex(let detail):
            return "The IMG cannot be indexed: \(detail)"
        }
    }
}
