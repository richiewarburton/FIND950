import Foundation

public struct S950ImageIndexSignature: Codable, Equatable, Sendable {
    public let canonicalPath: String
    public let byteSize: UInt64
    public let modifiedAt: Date

    public init(canonicalPath: String, byteSize: UInt64, modifiedAt: Date) {
        self.canonicalPath = canonicalPath
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
    }
}

public struct S950LibraryIndexRecord: Codable, Equatable, Sendable {
    public let signature: S950ImageIndexSignature
    public let catalog: S950ImageCatalog

    public init(signature: S950ImageIndexSignature, catalog: S950ImageCatalog) {
        self.signature = signature
        self.catalog = catalog
    }
}

public struct S950LibraryIndexDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let records: [S950LibraryIndexRecord]

    public init(
        version: Int = S950LibraryIndexDocument.currentVersion,
        records: [S950LibraryIndexRecord] = []
    ) {
        self.version = version
        self.records = records
    }

    public static func load(from url: URL) -> S950LibraryIndexDocument {
        guard let data = try? Data(contentsOf: url),
              let document = try? JSONDecoder().decode(Self.self, from: data),
              document.version == currentVersion
        else { return S950LibraryIndexDocument() }
        return document
    }

    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public func cachedCollection(folderURLs: [URL]) -> S950LibraryCollection {
        let folderPaths = Set(folderURLs.map { $0.standardizedFileURL.path })
        let images = records.compactMap { record -> S950ImageCatalog? in
            guard let folder = record.catalog.libraryFolderURL,
                  folderPaths.contains(folder.standardizedFileURL.path)
            else { return nil }
            return Self.reclassified(record.catalog)
        }
        return S950LibraryCollection(
            folderURLs: folderURLs,
            images: Self.sortedUnique(images),
            failures: []
        )
    }

    static func sortedUnique(_ images: [S950ImageCatalog]) -> [S950ImageCatalog] {
        Dictionary(grouping: images, by: { $0.imageURL.standardizedFileURL })
            .compactMap { $0.value.first }
            .sorted { left, right in
                let nameOrder = left.name.localizedStandardCompare(right.name)
                return nameOrder == .orderedSame
                    ? left.imageURL.path < right.imageURL.path
                    : nameOrder == .orderedAscending
            }
    }

    static func reclassified(_ catalog: S950ImageCatalog) -> S950ImageCatalog {
        S950ImageCatalog(
            imageURL: catalog.imageURL,
            name: catalog.name,
            volumes: catalog.volumes.map { volume in
                S950VolumeCatalog(
                    name: volume.name,
                    path: volume.path,
                    entries: volume.entries.map { entry in
                        S950LibraryEntry(
                            index: entry.index,
                            name: entry.name,
                            byteSize: entry.byteSize,
                            kind: S950EntryKind.classify(filename: entry.name),
                            sampleReferences: entry.sampleReferences,
                            sampleRate: entry.sampleRate
                        )
                    }
                )
            },
            libraryFolderURL: catalog.libraryFolderURL
        )
    }
}

public struct S950IncrementalScanResult: Sendable {
    public let collection: S950LibraryCollection
    public let index: S950LibraryIndexDocument
    public let reusedImageCount: Int
    public let inspectedImageCount: Int

    public init(
        collection: S950LibraryCollection,
        index: S950LibraryIndexDocument,
        reusedImageCount: Int,
        inspectedImageCount: Int
    ) {
        self.collection = collection
        self.index = index
        self.reusedImageCount = reusedImageCount
        self.inspectedImageCount = inspectedImageCount
    }
}
