import Darwin
import Foundation

@_silgen_name("flock")
private func sharedTagFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

public struct LibraryTag: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var colorHex: String

    public init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

public enum SharedTagTargetKind: String, Codable, Sendable {
    case image
    case program
    case sample
    case other
}

public struct SharedTagTarget: Codable, Equatable, Hashable, Sendable {
    public let kind: SharedTagTargetKind
    public let imagePath: String
    public let volumePath: String?
    public let filename: String?

    public init(
        kind: SharedTagTargetKind,
        imagePath: String,
        volumePath: String? = nil,
        filename: String? = nil
    ) {
        self.kind = kind
        self.imagePath = Self.canonicalImagePath(imagePath)
        self.volumePath = volumePath.map(Self.normalizedVolumePath)
        self.filename = filename.map(Self.normalizedFilename)
    }

    public static func image(_ imageURL: URL) -> SharedTagTarget {
        SharedTagTarget(kind: .image, imagePath: imageURL.path)
    }

    public static func entry(
        imageURL: URL,
        volumePath: String,
        kind: SharedTagTargetKind,
        filename: String
    ) -> SharedTagTarget {
        precondition(kind != .image, "An IMG target cannot have a volume or filename.")
        return SharedTagTarget(
            kind: kind,
            imagePath: imageURL.path,
            volumePath: volumePath,
            filename: filename
        )
    }

    public var storageKey: String {
        let components: [String]
        switch kind {
        case .image:
            components = ["v2", kind.rawValue, imagePath]
        case .program, .sample, .other:
            components = [
                "v2",
                kind.rawValue,
                imagePath,
                volumePath ?? "",
                filename ?? ""
            ]
        }
        return components.map(Self.encodedComponent).joined(separator: "|")
    }

    private static func canonicalImagePath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    private static func normalizedVolumePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1 else { return trimmed.isEmpty ? "/" : trimmed }
        return trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
    }

    private static func normalizedFilename(_ filename: String) -> String {
        filename.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func encodedComponent(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
    }
}

public struct SharedTagDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var tags: [LibraryTag]
    public var assignments: [String: Set<UUID>]

    public init(
        schemaVersion: Int = SharedTagDocument.currentSchemaVersion,
        tags: [LibraryTag] = [],
        assignments: [String: Set<UUID>] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.tags = tags
        self.assignments = assignments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        tags = try container.decodeIfPresent([LibraryTag].self, forKey: .tags) ?? []
        assignments = try container.decodeIfPresent(
            [String: Set<UUID>].self,
            forKey: .assignments
        ) ?? [:]
    }

    public func tags(for target: SharedTagTarget) -> [LibraryTag] {
        let assigned = assignments[target.storageKey] ?? []
        return tags.filter { assigned.contains($0.id) }
    }

    public func isAssigned(_ tagID: UUID, to target: SharedTagTarget) -> Bool {
        assignments[target.storageKey]?.contains(tagID) == true
    }

    public mutating func toggle(_ tagID: UUID, for target: SharedTagTarget) {
        set(!isAssigned(tagID, to: target), tagID: tagID, for: target)
    }

    public mutating func set(
        _ assigned: Bool,
        tagID: UUID,
        for target: SharedTagTarget
    ) {
        guard tags.contains(where: { $0.id == tagID }) else { return }
        let key = target.storageKey
        var tagIDs = assignments[key] ?? []
        if assigned {
            tagIDs.insert(tagID)
        } else {
            tagIDs.remove(tagID)
        }
        if tagIDs.isEmpty {
            assignments.removeValue(forKey: key)
        } else {
            assignments[key] = tagIDs
        }
    }

    public mutating func removeAssignments(for targets: [SharedTagTarget]) {
        for target in targets {
            assignments.removeValue(forKey: target.storageKey)
        }
    }

    public mutating func moveAssignments(
        from source: SharedTagTarget,
        to destination: SharedTagTarget
    ) {
        let sourceKey = source.storageKey
        let destinationKey = destination.storageKey
        guard sourceKey != destinationKey,
              let sourceTags = assignments.removeValue(forKey: sourceKey)
        else { return }
        assignments[destinationKey, default: []].formUnion(sourceTags)
    }

    public mutating func removeTag(_ tagID: UUID) {
        tags.removeAll { $0.id == tagID }
        for key in Array(assignments.keys) {
            assignments[key]?.remove(tagID)
            if assignments[key]?.isEmpty == true {
                assignments.removeValue(forKey: key)
            }
        }
    }

    fileprivate mutating func normalize() {
        schemaVersion = Self.currentSchemaVersion
        var seen = Set<UUID>()
        tags = tags.filter { seen.insert($0.id).inserted }
        let validTagIDs = Set(tags.map(\.id))
        for key in Array(assignments.keys) {
            assignments[key]?.formIntersection(validTagIDs)
            if assignments[key]?.isEmpty == true {
                assignments.removeValue(forKey: key)
            }
        }
    }
}

public enum SharedTagLibraryError: LocalizedError {
    case unsupportedSchema(Int)
    case lockFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "The shared 950TOOLS tag library uses unsupported schema version \(version)."
        case .lockFailed(let path, let errorNumber):
            return "Could not lock the shared 950TOOLS tag library at \(path) (errno \(errorNumber))."
        }
    }
}

public final class SharedTagLibrary {
    public static let sharedDefaultsSuiteName = "com.e45recordings.950TOOLS"
    public static let directoryDefaultsKey = "SharedTagLibrary.directory"
    public static let distributedChangeNotification = Notification.Name(
        "com.e45recordings.950TOOLS.TagsChanged"
    )
    public static let filename = "tags-v2.json"

    public let directoryURL: URL
    public var fileURL: URL {
        directoryURL.appendingPathComponent(Self.filename, isDirectory: false)
    }

    public static var defaultDirectoryURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport.appendingPathComponent("FIND950", isDirectory: true)
    }

    private var lockFileURL: URL {
        directoryURL.appendingPathComponent("tags-v2.lock", isDirectory: false)
    }

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL.standardizedFileURL
    }

    public static func resolvedDirectoryURL(
        preferredDirectoryURL: URL? = nil
    ) -> URL {
        if let configured = UserDefaults(suiteName: sharedDefaultsSuiteName)?
            .string(forKey: directoryDefaultsKey),
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
                .standardizedFileURL
        }
        if let preferredDirectoryURL {
            setConfiguredDirectoryURL(preferredDirectoryURL)
            return preferredDirectoryURL.standardizedFileURL
        }
        if let find950Directory = UserDefaults(suiteName: "com.e45recordings.FIND950")?
            .string(forKey: "FIND950.libraryDataDirectory"),
           !find950Directory.isEmpty {
            let url = URL(fileURLWithPath: find950Directory, isDirectory: true)
                .standardizedFileURL
            setConfiguredDirectoryURL(url)
            return url
        }
        let url = defaultDirectoryURL
        setConfiguredDirectoryURL(url)
        return url
    }

    public static func setConfiguredDirectoryURL(_ url: URL) {
        let defaults = UserDefaults(suiteName: sharedDefaultsSuiteName)
        defaults?.set(url.standardizedFileURL.path, forKey: directoryDefaultsKey)
    }

    public static func activateDirectoryURL(_ url: URL) {
        let directory = url.standardizedFileURL
        setConfiguredDirectoryURL(directory)
        postChangeNotification(for: directory.appendingPathComponent(filename))
    }

    public func bootstrap(legacyMetadataURL: URL? = nil) throws -> SharedTagDocument {
        try withLock(exclusive: true) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return try loadUnlocked()
            }
            var document = SharedTagDocument()
            if let legacyMetadataURL,
               FileManager.default.fileExists(atPath: legacyMetadataURL.path) {
                let data = try Data(contentsOf: legacyMetadataURL)
                let legacy = try JSONDecoder().decode(SharedTagDocument.self, from: data)
                document = Self.migratingLegacyDocument(legacy)
            }
            try writeUnlocked(document)
            return document
        }
    }

    public func load() throws -> SharedTagDocument {
        try withLock(exclusive: false) { try loadUnlocked() }
    }

    @discardableResult
    public func update(
        _ mutation: (inout SharedTagDocument) throws -> Void
    ) throws -> SharedTagDocument {
        let document = try withLock(exclusive: true) {
            var latest = try loadUnlocked()
            try mutation(&latest)
            latest.normalize()
            try writeUnlocked(latest)
            return latest
        }
        DistributedNotificationCenter.default().postNotificationName(
            Self.distributedChangeNotification,
            object: nil,
            userInfo: ["path": fileURL.path],
            deliverImmediately: true
        )
        return document
    }

    @discardableResult
    public func replace(with document: SharedTagDocument) throws -> SharedTagDocument {
        try update { $0 = document }
    }

    public func export(to destinationURL: URL) throws {
        let document = try load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(
            to: destinationURL.standardizedFileURL,
            options: .atomic
        )
    }

    public func relocate(
        to destinationDirectoryURL: URL,
        activateSharedLocation: Bool = true
    ) throws -> SharedTagLibrary {
        let destinationURL = destinationDirectoryURL.standardizedFileURL
        guard destinationURL != directoryURL else {
            if activateSharedLocation { Self.activateDirectoryURL(destinationURL) }
            return self
        }
        let document = try load()
        let destination = SharedTagLibrary(directoryURL: destinationURL)
        try destination.withLock(exclusive: true) {
            try destination.writeUnlocked(document)
        }
        if activateSharedLocation { Self.activateDirectoryURL(destinationURL) }
        return destination
    }

    private func loadUnlocked() throws -> SharedTagDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return SharedTagDocument()
        }
        let data = try Data(contentsOf: fileURL)
        var document = try JSONDecoder().decode(SharedTagDocument.self, from: data)
        guard document.schemaVersion <= SharedTagDocument.currentSchemaVersion else {
            throw SharedTagLibraryError.unsupportedSchema(document.schemaVersion)
        }
        if document.schemaVersion < SharedTagDocument.currentSchemaVersion {
            document = Self.migratingLegacyDocument(document)
        }
        document.normalize()
        return document
    }

    private func writeUnlocked(_ source: SharedTagDocument) throws {
        var document = source
        document.normalize()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private func withLock<T>(
        exclusive: Bool,
        operation: () throws -> T
    ) throws -> T {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let descriptor = Darwin.open(
            lockFileURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw SharedTagLibraryError.lockFailed(lockFileURL.path, errno)
        }
        defer { Darwin.close(descriptor) }
        let operationFlag = exclusive ? LOCK_EX : LOCK_SH
        guard sharedTagFlock(descriptor, operationFlag) == 0 else {
            throw SharedTagLibraryError.lockFailed(lockFileURL.path, errno)
        }
        defer { _ = sharedTagFlock(descriptor, LOCK_UN) }
        return try operation()
    }

    private static func migratingLegacyDocument(
        _ legacy: SharedTagDocument
    ) -> SharedTagDocument {
        var migrated = SharedTagDocument(tags: legacy.tags)
        for (key, tagIDs) in legacy.assignments {
            if key.hasPrefix("djI=|") {
                migrated.assignments[key, default: []].formUnion(tagIDs)
                continue
            }
            let fields = key.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 4 else { continue }
            let filename = String(fields[fields.count - 1])
            let volumePath = String(fields[fields.count - 3])
            let imagePath = fields.dropLast(3).map(String.init).joined(separator: "|")
            let targetKind: SharedTagTargetKind
            switch (filename as NSString).pathExtension.uppercased() {
            case "P", "P1", "P3", "P9": targetKind = .program
            case "S", "S9": targetKind = .sample
            default: continue
            }
            let target = SharedTagTarget(
                kind: targetKind,
                imagePath: imagePath,
                volumePath: volumePath,
                filename: filename
            )
            migrated.assignments[target.storageKey, default: []].formUnion(tagIDs)
        }
        migrated.normalize()
        return migrated
    }

    private static func postChangeNotification(for fileURL: URL) {
        DistributedNotificationCenter.default().postNotificationName(
            distributedChangeNotification,
            object: nil,
            userInfo: ["path": fileURL.path],
            deliverImmediately: true
        )
    }
}
