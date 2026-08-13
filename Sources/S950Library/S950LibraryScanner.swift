import Foundation

public struct S950LibraryScanner: Sendable {
    private struct DiscoveredImage {
        let imageURL: URL
        let libraryFolderURL: URL
        let signature: S950ImageIndexSignature
    }

    public let helperURL: URL

    public init(helperURL: URL) {
        self.helperURL = helperURL
    }

    public func scan(folderURL: URL, recursive: Bool = false) async throws -> S950LibraryScan {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw S950LibraryError.folderNotFound(folderURL.path) }

        let images = try imageURLs(in: folderURL, recursive: recursive)
        var catalogs: [S950ImageCatalog] = []
        var failures: [S950ScanFailure] = []

        for imageURL in images {
            do {
                let catalog = try await inspect(imageURL: imageURL)
                catalogs.append(S950ImageCatalog(
                    imageURL: catalog.imageURL,
                    name: catalog.name,
                    volumes: catalog.volumes,
                    libraryFolderURL: folderURL
                ))
            } catch {
                failures.append(S950ScanFailure(
                    imageURL: imageURL,
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ))
            }
        }
        return S950LibraryScan(folderURL: folderURL, images: catalogs, failures: failures)
    }

    public func scan(folderURLs: [URL], recursive: Bool = false) async -> S950LibraryCollection {
        var images: [S950ImageCatalog] = []
        var failures: [S950ScanFailure] = []
        for folderURL in folderURLs {
            do {
                let result = try await scan(folderURL: folderURL, recursive: recursive)
                images.append(contentsOf: result.images)
                failures.append(contentsOf: result.failures)
            } catch {
                failures.append(S950ScanFailure(
                    imageURL: folderURL,
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                ))
            }
        }
        let uniqueImages = S950LibraryIndexDocument.sortedUnique(images)
        return S950LibraryCollection(folderURLs: folderURLs, images: uniqueImages, failures: failures)
    }

    public func scanIncrementally(
        folderURLs: [URL],
        recursive: Bool = false,
        cached index: S950LibraryIndexDocument
    ) async -> S950IncrementalScanResult {
        var cachedByPath: [String: S950LibraryIndexRecord] = [:]
        for record in index.records {
            cachedByPath[record.signature.canonicalPath] = record
        }
        var discoveredByPath: [String: DiscoveredImage] = [:]
        var failures: [S950ScanFailure] = []

        for folderURL in folderURLs.map(\.standardizedFileURL).sorted(by: {
            $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }) {
            do {
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(
                    atPath: folderURL.path,
                    isDirectory: &isDirectory
                ), isDirectory.boolValue else {
                    throw S950LibraryError.folderNotFound(folderURL.path)
                }
                for imageURL in try imageURLs(in: folderURL, recursive: recursive) {
                    do {
                        let canonical = imageURL.standardizedFileURL.resolvingSymlinksInPath()
                        guard discoveredByPath[canonical.path] == nil else { continue }
                        discoveredByPath[canonical.path] = DiscoveredImage(
                            imageURL: canonical,
                            libraryFolderURL: folderURL,
                            signature: try indexSignature(for: canonical)
                        )
                    } catch {
                        failures.append(S950ScanFailure(
                            imageURL: imageURL,
                            message: (error as? LocalizedError)?.errorDescription
                                ?? error.localizedDescription
                        ))
                    }
                }
            } catch {
                failures.append(S950ScanFailure(
                    imageURL: folderURL,
                    message: (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                ))
            }
        }

        var records: [S950LibraryIndexRecord] = []
        var reusedImageCount = 0
        var inspectedImageCount = 0
        for discovered in discoveredByPath.values.sorted(by: {
            $0.imageURL.path.localizedStandardCompare($1.imageURL.path)
                == .orderedAscending
        }) {
            if let cached = cachedByPath[discovered.signature.canonicalPath],
               cached.signature == discovered.signature {
                records.append(S950LibraryIndexRecord(
                    signature: discovered.signature,
                    catalog: catalog(
                        cached.catalog,
                        imageURL: discovered.imageURL,
                        libraryFolderURL: discovered.libraryFolderURL
                    )
                ))
                reusedImageCount += 1
                continue
            }

            do {
                try Task.checkCancellation()
                let inspected = try await inspect(imageURL: discovered.imageURL)
                records.append(S950LibraryIndexRecord(
                    signature: discovered.signature,
                    catalog: catalog(
                        inspected,
                        imageURL: discovered.imageURL,
                        libraryFolderURL: discovered.libraryFolderURL
                    )
                ))
                inspectedImageCount += 1
            } catch is CancellationError {
                return S950IncrementalScanResult(
                    collection: index.cachedCollection(folderURLs: folderURLs),
                    index: index,
                    reusedImageCount: reusedImageCount,
                    inspectedImageCount: inspectedImageCount
                )
            } catch {
                failures.append(S950ScanFailure(
                    imageURL: discovered.imageURL,
                    message: (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                ))
            }
        }

        let updatedIndex = S950LibraryIndexDocument(records: records)
        return S950IncrementalScanResult(
            collection: S950LibraryCollection(
                folderURLs: folderURLs,
                images: S950LibraryIndexDocument.sortedUnique(records.map(\.catalog)),
                failures: failures
            ),
            index: updatedIndex,
            reusedImageCount: reusedImageCount,
            inspectedImageCount: inspectedImageCount
        )
    }

    public func inspect(imageURL: URL) async throws -> S950ImageCatalog {
        let session = AkaiUtilSession()
        try await session.open(imageURL: imageURL, helperURL: helperURL)
        do {
            let recursiveListing = try await session.send("dirrec")
            var paths = AkaiOutputParser.volumes(from: recursiveListing)
            if paths.isEmpty, let current = AkaiPrompt.path(in: recursiveListing) { paths = [current] }

            var volumes: [S950VolumeCatalog] = []
            let workspace = URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("s950-index-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workspace) }
            _ = try await session.send("lcd \(workspace.path)")
            for path in paths {
                _ = try await session.send("cd \(path.replacingOccurrences(of: " ", with: "_"))")
                let listing = try await session.send("dir")
                let entries = await entriesWithNativeMetadata(
                    AkaiOutputParser.directory(from: listing),
                    session: session,
                    workspace: workspace
                )
                volumes.append(S950VolumeCatalog(
                    name: path.split(separator: "/").last.map(String.init) ?? path,
                    path: path,
                    entries: entries
                ))
            }
            await session.close()
            return S950ImageCatalog(
                imageURL: imageURL,
                name: imageURL.deletingPathExtension().lastPathComponent,
                volumes: volumes
            )
        } catch {
            await session.close()
            throw error
        }
    }

    private func entriesWithNativeMetadata(
        _ entries: [S950LibraryEntry],
        session: AkaiUtilSession,
        workspace: URL
    ) async -> [S950LibraryEntry] {
        var result: [S950LibraryEntry] = []
        for entry in entries {
            let fileExtension = (entry.name as NSString).pathExtension.uppercased()
            guard (entry.kind == .program && fileExtension == "P9")
                    || (entry.kind == .sample && fileExtension == "S9") else {
                result.append(entry)
                continue
            }
            do {
                for file in try nativeFiles(in: workspace) {
                    try? FileManager.default.removeItem(at: file)
                }
                _ = try await session.send("geti \(entry.index)")
                guard let exported = try nativeFiles(in: workspace).first(where: {
                    $0.pathExtension.caseInsensitiveCompare(fileExtension) == .orderedSame
                }) else {
                    result.append(entry)
                    continue
                }
                let data = try Data(contentsOf: exported)
                if entry.kind == .program {
                    result.append(S950LibraryEntry(
                        index: entry.index,
                        name: entry.name,
                        byteSize: entry.byteSize,
                        kind: entry.kind,
                        sampleReferences: try P9ReferenceParser.sampleNames(in: data)
                    ))
                } else {
                    result.append(S950LibraryEntry(
                        index: entry.index,
                        name: entry.name,
                        byteSize: entry.byteSize,
                        kind: entry.kind,
                        sampleRate: S9MetadataParser.sampleRate(in: data)
                    ))
                }
            } catch {
                result.append(entry)
            }
        }
        return result
    }

    public func exportSampleForAudition(
        imageURL: URL,
        volumePath: String,
        sample: S950LibraryEntry,
        destinationFolder: URL
    ) async throws -> URL {
        guard sample.kind == .sample, sample.index > 0 else { throw S950LibraryError.invalidSample }
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        guard !destinationFolder.path.contains(where: \.isWhitespace) else {
            throw S950LibraryError.temporaryExportFailed(sample.name)
        }

        let session = AkaiUtilSession()
        try await session.open(imageURL: imageURL, helperURL: helperURL)
        do {
            _ = try await session.send("cd \(volumePath.replacingOccurrences(of: " ", with: "_"))")
            _ = try await session.send("lcd \(destinationFolder.path)")
            let before = Set(try wavFiles(in: destinationFolder).map(\.standardizedFileURL))
            _ = try await session.send("sample2wavi \(sample.index)")
            let exported = try wavFiles(in: destinationFolder).first {
                !before.contains($0.standardizedFileURL)
            }
            await session.close()
            guard let exported else { throw S950LibraryError.temporaryExportFailed(sample.name) }
            return exported
        } catch {
            await session.close()
            throw error
        }
    }

    private func imageURLs(in folderURL: URL, recursive: Bool) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        let options: FileManager.DirectoryEnumerationOptions = recursive ? [.skipsHiddenFiles] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: options
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter {
            $0.pathExtension.caseInsensitiveCompare("img") == .orderedSame
        }.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    private func indexSignature(for imageURL: URL) throws -> S950ImageIndexSignature {
        let values = try imageURL.resourceValues(forKeys: [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
        ])
        guard values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              let modifiedAt = values.contentModificationDate
        else {
            throw S950LibraryError.invalidImageForIndex(
                "It is not a non-empty regular file."
            )
        }
        return S950ImageIndexSignature(
            canonicalPath: imageURL.path,
            byteSize: UInt64(size),
            modifiedAt: modifiedAt
        )
    }

    private func catalog(
        _ catalog: S950ImageCatalog,
        imageURL: URL,
        libraryFolderURL: URL
    ) -> S950ImageCatalog {
        S950ImageCatalog(
            imageURL: imageURL,
            name: imageURL.deletingPathExtension().lastPathComponent,
            volumes: S950LibraryIndexDocument.reclassified(catalog).volumes,
            libraryFolderURL: libraryFolderURL
        )
    }

    private func wavFiles(in folderURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.caseInsensitiveCompare("wav") == .orderedSame }
    }

    private func nativeFiles(in folderURL: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { ["P9", "S9"].contains($0.pathExtension.uppercased()) }
    }
}

public enum AkaiUtilLocator {
    public static func locate(explicitPath: String? = nil) throws -> URL {
        var candidates: [String] = []
        if let explicitPath { candidates.append(explicitPath) }
        if let environment = ProcessInfo.processInfo.environment["AKAIUTIL_PATH"] { candidates.append(environment) }
        candidates += [
            "/Applications/EDIT950.app/Contents/Resources/akaiutil",
            "/Applications/AKAI Image Manager.app/Contents/Resources/akaiutil",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/EDIT950.app/Contents/Resources/akaiutil").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/AKAI Image Manager.app/Contents/Resources/akaiutil").path
        ]
        if let path = executableOnPath(named: "akaiutil") { candidates.append(path) }
        guard let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw S950LibraryError.helperNotFound
        }
        return URL(fileURLWithPath: match)
    }

    private static func executableOnPath(named name: String) -> String? {
        for directory in ProcessInfo.processInfo.environment["PATH", default: ""].split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
