import Darwin
import Foundation

public struct RemovableMediaCleanupPolicy: Codable, Equatable, Sendable {
    public static let defaultNames = [
        ".DS_Store",
        "._*",
        "._AppleDouble",
        ".AppleDouble",
        ".fseventsd",
        ".VolumeIcon.icns",
        ".TemporaryItems",
        ".DocumentRevisions-V100",
        ".Spotlight-V100",
        ".Trashes",
        ".localized",
        ".AppleDB",
        ".apdisk",
        "Thumbs.db",
        "Desktop.ini",
        ".syncing_db",
        ".Trash",
        ".metadata_never_index",
        ".bzvol",
        ".dbxignore",
        "System Volume Information",
        "$RECYCLE.BIN",
        "RECYCLED"
    ]

    public var disabledDefaultNames: Set<String>
    public var customNames: [String]
    public var exceptions: [String]

    public init(
        disabledDefaultNames: Set<String> = [],
        customNames: [String] = [],
        exceptions: [String] = []
    ) {
        self.disabledDefaultNames = disabledDefaultNames
        self.customNames = customNames
        self.exceptions = exceptions
    }

    public func isDefaultEnabled(_ name: String) -> Bool {
        !disabledDefaultNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    public var activeNames: Set<String> {
        let defaults = Self.defaultNames.filter(isDefaultEnabled)
        return Set((defaults + customNames).compactMap(Self.normalizedLeafName))
    }

    public mutating func setDefault(_ name: String, enabled: Bool) {
        disabledDefaultNames = Set(disabledDefaultNames.filter {
            $0.caseInsensitiveCompare(name) != .orderedSame
        })
        if !enabled { disabledDefaultNames.insert(name) }
    }

    public mutating func addCustomName(_ name: String) throws {
        guard let normalized = Self.normalizedLeafName(name) else {
            throw RemovableMediaCleanupError.invalidRule(name)
        }
        guard !customNames.contains(where: {
            $0.caseInsensitiveCompare(normalized) == .orderedSame
        }) else { return }
        customNames.append(normalized)
        customNames.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public mutating func addException(_ exception: String) throws {
        guard let normalized = Self.normalizedException(exception) else {
            throw RemovableMediaCleanupError.invalidException(exception)
        }
        guard !exceptions.contains(where: {
            $0.caseInsensitiveCompare(normalized) == .orderedSame
        }) else { return }
        exceptions.append(normalized)
        exceptions.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public static func normalizedLeafName(_ value: String) -> String? {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              name != ".",
              name != "..",
              name.utf8.count <= 255,
              !name.contains("/"),
              !name.contains("\\"),
              name.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              })
        else { return nil }
        return name
    }

    public static func normalizedException(_ value: String) -> String? {
        var path = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while path.hasPrefix("/") { path.removeFirst() }
        while path.hasSuffix("/") { path.removeLast() }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              path.utf8.count <= 4_096,
              components.allSatisfy({
                  !$0.isEmpty && $0 != "." && $0 != ".."
                      && $0.unicodeScalars.allSatisfy {
                          !CharacterSet.controlCharacters.contains($0)
                      }
              })
        else { return nil }
        return components.joined(separator: "/")
    }
}

public struct RemovableMediaCleanupCandidate: Equatable, Sendable {
    public let url: URL
    public let relativePath: String
    public let isDirectory: Bool

    public init(url: URL, relativePath: String, isDirectory: Bool) {
        self.url = url
        self.relativePath = relativePath
        self.isDirectory = isDirectory
    }
}

public struct RemovableMediaCleanupFailure: Equatable, Sendable {
    public let relativePath: String
    public let message: String

    public init(relativePath: String, message: String) {
        self.relativePath = relativePath
        self.message = message
    }
}

public struct RemovableMediaCleanupResult: Equatable, Sendable {
    public let removedPaths: [String]
    public let failures: [RemovableMediaCleanupFailure]

    public init(
        removedPaths: [String],
        failures: [RemovableMediaCleanupFailure]
    ) {
        self.removedPaths = removedPaths
        self.failures = failures
    }
}

public enum RemovableMediaCleanupError: LocalizedError, Equatable {
    case invalidVolumeRoot(String)
    case invalidRule(String)
    case invalidException(String)
    case enumerationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidVolumeRoot(let path):
            return "Refusing to clean an invalid media root: \(path)"
        case .invalidRule(let name):
            return "Cleanup names must be one exact filename or folder name, without slashes: \(name)"
        case .invalidException(let path):
            return "Cleanup exceptions must be one name or a relative path without '..': \(path)"
        case .enumerationFailed(let path):
            return "Couldn’t fully inspect the removable media at \(path). Check that FIND950 has Full Disk Access."
        }
    }
}

public enum RemovableMediaCleaner {
    public static func candidates(
        on volumeURL: URL,
        policy: RemovableMediaCleanupPolicy,
        fileManager: FileManager = .default
    ) throws -> [RemovableMediaCleanupCandidate] {
        let requestedRoot = volumeURL.standardizedFileURL
        let root = requestedRoot.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard root.isFileURL,
              root.path != "/",
              root.path != "/Volumes",
              fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { throw RemovableMediaCleanupError.invalidVolumeRoot(root.path) }

        let activeNames = Set(policy.activeNames.map { $0.foldingForCleanup })
        guard !activeNames.isEmpty else { return [] }
        let exceptions = policy.exceptions.compactMap(
            RemovableMediaCleanupPolicy.normalizedException
        )
        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey
        ]
        var matches: [RemovableMediaCleanupCandidate] = []
        var pendingDirectories = [root]
        while let directory = pendingDirectories.popLast() {
            let entries = try directoryEntries(at: directory)
            for url in entries {
            let candidatePath = url.standardizedFileURL.path
            guard let matchingRootPath = [root.path, requestedRoot.path].first(where: {
                candidatePath.hasPrefix($0 + "/")
            }) else { continue }
            let relativePath = String(
                candidatePath.dropFirst(matchingRootPath.count + 1)
            )
            guard !relativePath.isEmpty else { continue }
            let values: URLResourceValues
            do {
                values = try url.resourceValues(forKeys: resourceKeys)
            } catch {
                throw RemovableMediaCleanupError.enumerationFailed(
                    "\(url.path): \(error.localizedDescription)"
                )
            }
            let isDirectory = values.isDirectory == true && values.isSymbolicLink != true
            let foldedName = url.lastPathComponent.foldingForCleanup
            let nameMatches = activeNames.contains(foldedName)
                || (activeNames.contains("._*") && foldedName.hasPrefix("._"))
            let isExcepted = exceptionMatches(relativePath, exceptions: exceptions)
            let containsException = exceptions.contains {
                $0.foldingForCleanup.hasPrefix(relativePath.foldingForCleanup + "/")
            }

            if nameMatches && !isExcepted && !containsException {
                matches.append(RemovableMediaCleanupCandidate(
                    url: url,
                    relativePath: relativePath,
                    isDirectory: isDirectory
                ))
            } else if isDirectory && values.isSymbolicLink != true {
                pendingDirectories.append(url)
            }
            }
        }
        return matches.sorted {
            let leftDepth = $0.relativePath.split(separator: "/").count
            let rightDepth = $1.relativePath.split(separator: "/").count
            if leftDepth != rightDepth { return leftDepth > rightDepth }
            return $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath)
                == .orderedAscending
        }
    }

    private static func directoryEntries(at directory: URL) throws -> [URL] {
        guard let stream = opendir(directory.path) else {
            throw RemovableMediaCleanupError.enumerationFailed(
                "\(directory.path): \(String(cString: strerror(errno)))"
            )
        }
        defer { closedir(stream) }

        var entries: [URL] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 {
                    throw RemovableMediaCleanupError.enumerationFailed(
                        "\(directory.path): \(String(cString: strerror(errno)))"
                    )
                }
                break
            }
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(
                    to: CChar.self,
                    capacity: Int(NAME_MAX) + 1
                ) { String(cString: $0) }
            }
            guard name != ".", name != ".." else { continue }
            entries.append(directory.appendingPathComponent(name))
        }
        return entries
    }

    public static func remove(
        _ candidates: [RemovableMediaCleanupCandidate],
        from volumeURL: URL,
        fileManager: FileManager = .default
    ) throws -> RemovableMediaCleanupResult {
        let root = volumeURL.standardizedFileURL.resolvingSymlinksInPath()
        guard root.isFileURL, root.path != "/", root.path != "/Volumes" else {
            throw RemovableMediaCleanupError.invalidVolumeRoot(root.path)
        }
        let requiredPrefix = root.path + "/"
        var removed: [String] = []
        var failures: [RemovableMediaCleanupFailure] = []
        for candidate in candidates {
            let target = candidate.url.standardizedFileURL.resolvingSymlinksInPath()
            guard target.path.hasPrefix(requiredPrefix), target.path != root.path else {
                failures.append(RemovableMediaCleanupFailure(
                    relativePath: candidate.relativePath,
                    message: "The cleanup target escaped the selected media root."
                ))
                continue
            }
            do {
                try fileManager.removeItem(at: target)
                removed.append(candidate.relativePath)
            } catch {
                failures.append(RemovableMediaCleanupFailure(
                    relativePath: candidate.relativePath,
                    message: error.localizedDescription
                ))
            }
        }
        return RemovableMediaCleanupResult(
            removedPaths: removed,
            failures: failures
        )
    }

    private static func exceptionMatches(
        _ relativePath: String,
        exceptions: [String]
    ) -> Bool {
        let foldedPath = relativePath.foldingForCleanup
        let foldedName = URL(fileURLWithPath: relativePath).lastPathComponent.foldingForCleanup
        return exceptions.contains { exception in
            let foldedException = exception.foldingForCleanup
            if exception.contains("/") {
                return foldedPath == foldedException
                    || foldedPath.hasPrefix(foldedException + "/")
            }
            return foldedName == foldedException
        }
    }
}

private extension String {
    var foldingForCleanup: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
