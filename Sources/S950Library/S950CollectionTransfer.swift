import Foundation

/// Builds the read-only FIND950 side of a collection export. EDIT950 re-opens
/// every source IMG, resolves exactly the selected native entries, and remains
/// the only process allowed to create the result. Unlike focused program export,
/// collection export intentionally does not add unselected P9 dependencies.
public struct S950CollectionTransfer: Sendable {
    public struct Selection: Sendable {
        public let sourceImage: URL
        public let volumePath: String
        public let entry: S950LibraryEntry

        public init(
            sourceImage: URL,
            volumePath: String,
            entry: S950LibraryEntry
        ) {
            self.sourceImage = sourceImage
            self.volumePath = volumePath
            self.entry = entry
        }
    }

    public init() {}

    public func prepareHandoff(
        selections: [Selection],
        sender: Tools950Protocol.Sender = .init(
            productID: "com.e45recordings.FIND950",
            version: "0.2.3",
            build: "5"
        ),
        createdAt: Date = Date(),
        lifetime: TimeInterval = Tools950Protocol.defaultLifetime,
        handoffRoot: URL? = nil
    ) throws -> Tools950Protocol.PreparedCollectionHandoff {
        guard !selections.isEmpty, selections.count <= 64 else {
            throw S950LibraryError.invalidHandoff(
                "A collection export must contain between 1 and 64 native entries."
            )
        }
        guard lifetime > 0, lifetime <= 24 * 60 * 60 else {
            throw S950LibraryError.invalidHandoff("The collection request expiry is outside protocol-v1 bounds.")
        }

        let requestCreatedAt = Date(
            timeIntervalSince1970: floor(createdAt.timeIntervalSince1970)
        )
        var sources: [Tools950Protocol.Source] = []
        var sourceIndexes: [String: Int] = [:]
        var items: [Tools950Protocol.CollectionItem] = []

        for selection in selections {
            guard selection.entry.kind == .program || selection.entry.kind == .sample,
                  selection.entry.index > 0,
                  selection.entry.index <= 65_535,
                  Self.bounded(selection.entry.name, maximum: 64),
                  selection.volumePath.hasPrefix("/"),
                  Self.bounded(selection.volumePath, maximum: 1_024),
                  !selection.volumePath.split(separator: "/").contains("..")
            else {
                throw S950LibraryError.invalidHandoff(
                    "A collected native entry has an invalid volume, index, name, or type."
                )
            }
            let expectedExtension = selection.entry.kind == .program ? "P9" : "S9"
            guard (selection.entry.name as NSString).pathExtension
                .caseInsensitiveCompare(expectedExtension) == .orderedSame
            else {
                throw S950LibraryError.invalidHandoff(
                    "(selection.entry.name) is not a native (expectedExtension) file."
                )
            }

            let sourceURL = selection.sourceImage.standardizedFileURL.resolvingSymlinksInPath()
            guard sourceURL.pathExtension.caseInsensitiveCompare("img") == .orderedSame,
                  sourceURL.path != "/",
                  Self.bounded(sourceURL.path, maximum: 4_096)
            else {
                throw S950LibraryError.invalidHandoff("A collection source path is outside protocol-v1 bounds.")
            }
            let sourceKey = sourceURL.path
            let sourceIndex: Int
            if let existing = sourceIndexes[sourceKey] {
                sourceIndex = existing
            } else {
                let values = try sourceURL.resourceValues(forKeys: [
                    .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
                ])
                guard values.isRegularFile == true,
                      let fileSize = values.fileSize,
                      fileSize > 0,
                      UInt64(fileSize) <= 34_359_738_368
                else {
                    throw S950LibraryError.invalidHandoff(
                        "Every collection source must be a bounded regular IMG file."
                    )
                }
                sourceIndex = sources.count
                sourceIndexes[sourceKey] = sourceIndex
                sources.append(
                    .init(
                        path: sourceURL.path,
                        sha256: try Tools950Protocol.sha256(of: sourceURL),
                        byteSize: UInt64(fileSize),
                        modifiedAt: values.contentModificationDate
                    )
                )
            }
            items.append(
                .init(
                    sourceIndex: sourceIndex,
                    volumePath: selection.volumePath,
                    directoryIndex: selection.entry.index,
                    filename: selection.entry.name,
                    kind: selection.entry.kind == .program ? "program" : "sample"
                )
            )
        }

        let requestID = UUID()
        let root = handoffRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("950TOOLS", isDirectory: true)
        let artifacts = root.appendingPathComponent(requestID.uuidString.lowercased(), isDirectory: true)
        guard !FileManager.default.fileExists(atPath: artifacts.path) else {
            throw S950LibraryError.invalidHandoff("The collection handoff directory already exists.")
        }
        try FileManager.default.createDirectory(
            at: artifacts,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        do {
            let requestURL = artifacts.appendingPathComponent(
                "request-\(requestID.uuidString.lowercased()).\(Tools950Protocol.requestExtension)"
            )
            let responseURL = artifacts.appendingPathComponent(
                "response-\(requestID.uuidString.lowercased()).json"
            )
            let request = Tools950Protocol.ExportCollectionRequest(
                protocolIdentifier: Tools950Protocol.protocolIdentifier,
                protocolVersion: Tools950Protocol.protocolVersion,
                messageType: "aim.export-collection.request",
                requestID: requestID,
                createdAt: requestCreatedAt,
                sender: sender,
                response: .init(
                    path: responseURL.path,
                    expiresAt: requestCreatedAt.addingTimeInterval(lifetime)
                ),
                sources: sources,
                items: items
            )
            let data = try Tools950Protocol.encoder().encode(request)
            guard data.count <= Tools950Protocol.maximumDocumentBytes else {
                throw S950LibraryError.invalidHandoff("The encoded collection request exceeds 65,536 bytes.")
            }
            try data.write(to: requestURL, options: [.atomic])
            return .init(
                request: request,
                requestURL: requestURL,
                responseURL: responseURL,
                artifactDirectory: artifacts
            )
        } catch {
            try? FileManager.default.removeItem(at: artifacts)
            throw error
        }
    }

    public func waitForTerminalResponse(
        to handoff: Tools950Protocol.PreparedCollectionHandoff,
        acknowledgementTimeout: TimeInterval = Tools950Protocol.acknowledgementTimeout,
        pollIntervalNanoseconds: UInt64 = 100_000_000,
        onAccepted: @Sendable (Tools950Protocol.OperationResponse) async -> Void = { _ in }
    ) async throws -> Tools950Protocol.OperationResponse {
        defer { handoff.cleanup() }
        let acknowledgementDeadline = Date().addingTimeInterval(acknowledgementTimeout)
        var accepted = false
        var lastData: Data?

        while Date() < handoff.request.response.expiresAt {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: handoff.responseURL.path) {
                let data = try Data(contentsOf: handoff.responseURL, options: [.mappedIfSafe])
                guard data.count <= Tools950Protocol.maximumDocumentBytes else {
                    throw S950LibraryError.invalidHandoff("EDIT950 returned an oversized response.")
                }
                if data != lastData {
                    let response = try Tools950Protocol.decoder().decode(
                        Tools950Protocol.OperationResponse.self,
                        from: data
                    )
                    guard response.protocolIdentifier == Tools950Protocol.protocolIdentifier,
                          response.messageType == "operation.response",
                          response.requestID == handoff.request.requestID,
                          response.protocolVersion == Tools950Protocol.protocolVersion
                    else {
                        throw S950LibraryError.invalidHandoff(
                            "EDIT950 returned a response for another request or protocol."
                        )
                    }
                    if response.status == .accepted {
                        accepted = true
                        await onAccepted(response)
                    } else {
                        return response
                    }
                    lastData = data
                }
            }
            if !accepted, Date() >= acknowledgementDeadline {
                throw S950LibraryError.acknowledgementTimeout
            }
            try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }
        throw S950LibraryError.responseExpired
    }

    private static func bounded(_ value: String, maximum: Int) -> Bool {
        !value.isEmpty
            && value.count <= maximum
            && !value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7f }
    }
}
