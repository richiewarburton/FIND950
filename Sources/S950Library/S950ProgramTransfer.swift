import Foundation

/// Constructs the read-only FIND950 side of a focused export and waits
/// for EDIT950's authoritative acknowledgement. It never opens AKAI Util and has no
/// destination, density, backup, formatting, or IMG-mutation API.
public struct S950ProgramTransfer: Sendable {
    public init() {}

    public func prepareHandoff(
        sourceImage: URL,
        sourceVolumePath: String,
        program: S950LibraryEntry,
        sourceEntries: [S950LibraryEntry],
        openInPLAY950AfterExport: Bool = false,
        exportMode: String = "image",
        sender: Tools950Protocol.Sender = .init(
            productID: "com.e45recordings.FIND950",
            version: "0.2.3",
            build: "5"
        ),
        createdAt: Date = Date(),
        lifetime: TimeInterval = Tools950Protocol.defaultLifetime,
        handoffRoot: URL? = nil
    ) throws -> Tools950Protocol.PreparedHandoff {
        let requestCreatedAt = Date(
            timeIntervalSince1970: floor(createdAt.timeIntervalSince1970)
        )
        let validSenderBuild = sender.build.map {
            Self.bounded($0, maximum: 64, allowEmpty: true)
        } ?? true
        guard program.kind == .program,
              program.index > 0,
              program.index <= 65_535,
              !program.name.isEmpty,
              program.name.count <= 64,
              Self.hasNoControlCharacters(program.name),
              (program.name as NSString).pathExtension.caseInsensitiveCompare("P9") == .orderedSame
        else { throw S950LibraryError.invalidProgram }
        guard sourceVolumePath.hasPrefix("/"),
              sourceVolumePath.count <= 1_024,
              Self.hasNoControlCharacters(sourceVolumePath),
              !sourceVolumePath.split(separator: "/").contains(".."),
              Self.bounded(sender.productID, maximum: 128, allowEmpty: false),
              Self.bounded(sender.version, maximum: 64, allowEmpty: false),
              validSenderBuild,
              lifetime > 0,
              lifetime <= 24 * 60 * 60
        else {
            throw S950LibraryError.invalidHandoff("The volume path or expiry is outside protocol-v1 bounds.")
        }

        let canonicalSource = sourceImage.standardizedFileURL.resolvingSymlinksInPath()
        guard canonicalSource.path.count <= 4_096,
              canonicalSource.pathExtension.caseInsensitiveCompare("img") == .orderedSame,
              Self.hasNoControlCharacters(canonicalSource.path)
        else {
            throw S950LibraryError.invalidHandoff(
                "The source IMG path is outside protocol-v1 bounds."
            )
        }
        let values = try canonicalSource.resourceValues(forKeys: [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey
        ])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              UInt64(fileSize) <= 34_359_738_368
        else {
            throw S950LibraryError.invalidHandoff("The source must be a bounded regular IMG file.")
        }
        let sourceHash = try Tools950Protocol.sha256(of: canonicalSource)

        let samples = Dictionary(grouping: sourceEntries.filter {
            $0.kind == .sample
                && ($0.name as NSString).pathExtension.caseInsensitiveCompare("S9") == .orderedSame
        }) {
            P9ReferenceParser.normalized(($0.name as NSString).deletingPathExtension)
        }
        var seen = Set<String>()
        let observed = try program.sampleReferences.compactMap { reference -> Tools950Protocol.Dependency? in
            let key = P9ReferenceParser.normalized(reference)
            guard !key.isEmpty, key != "2 SAMPLE", seen.insert(key).inserted else { return nil }
            if let match = samples[key], match.count == 1, let entry = match.first,
               entry.index > 0,
               entry.index <= 65_535,
               Self.bounded(entry.name, maximum: 64, allowEmpty: false) {
                return .init(directoryIndex: entry.index, filename: entry.name, internalName: nil)
            }
            let boundedBase = String(reference.trimmingCharacters(in: .whitespacesAndNewlines).prefix(61))
            guard !boundedBase.isEmpty else {
                throw S950LibraryError.invalidHandoff("An observed dependency has no usable native name.")
            }
            let filename = (boundedBase as NSString).pathExtension.isEmpty
                ? "\(boundedBase).S9" : boundedBase
            return .init(directoryIndex: nil, filename: filename, internalName: nil)
        }
        guard observed.count <= Tools950Protocol.maximumDependencyCount else {
            throw S950LibraryError.invalidHandoff("The observed dependency list exceeds 128 entries.")
        }

        let requestID = Tools950Protocol.deterministicRequestID(
            sourcePath: canonicalSource.path,
            sourceSHA256: sourceHash,
            volumePath: sourceVolumePath,
            directoryIndex: program.index,
            filename: program.name,
            createdAt: requestCreatedAt,
            exportMode: exportMode
        )
        let root = handoffRoot ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("950TOOLS", isDirectory: true)
        let artifacts = root.appendingPathComponent(requestID.uuidString.lowercased(), isDirectory: true)
        guard !FileManager.default.fileExists(atPath: artifacts.path) else {
            throw S950LibraryError.invalidHandoff("The deterministic handoff directory already exists.")
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
            let request = Tools950Protocol.ExportProgramRequest(
                protocolIdentifier: Tools950Protocol.protocolIdentifier,
                protocolVersion: Tools950Protocol.protocolVersion,
                messageType: "aim.export-program.request",
                requestID: requestID,
                createdAt: requestCreatedAt,
                sender: sender,
                response: .init(
                    path: responseURL.path,
                    expiresAt: requestCreatedAt.addingTimeInterval(lifetime)
                ),
                source: .init(
                    path: canonicalSource.path,
                    sha256: sourceHash,
                    byteSize: UInt64(fileSize),
                    modifiedAt: values.contentModificationDate
                ),
                program: .init(
                    volumePath: sourceVolumePath,
                    directoryIndex: program.index,
                    filename: program.name,
                    internalName: nil
                ),
                observedDependencies: observed,
                openInPLAY950AfterExport: openInPLAY950AfterExport,
                exportMode: exportMode
            )
            let data = try Tools950Protocol.encoder().encode(request)
            guard data.count <= Tools950Protocol.maximumDocumentBytes else {
                throw S950LibraryError.invalidHandoff("The encoded request exceeds 65,536 bytes.")
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
        to handoff: Tools950Protocol.PreparedHandoff,
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
                          response.requestID == handoff.request.requestID
                    else {
                        throw S950LibraryError.invalidHandoff("EDIT950 returned a response for another request or protocol.")
                    }
                    guard response.protocolVersion == Tools950Protocol.protocolVersion else {
                        throw S950LibraryError.unsupportedProtocolVersion(response.protocolVersion)
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

    private static func bounded(
        _ value: String,
        maximum: Int,
        allowEmpty: Bool
    ) -> Bool {
        (allowEmpty || !value.isEmpty)
            && value.count <= maximum
            && hasNoControlCharacters(value)
    }

    private static func hasNoControlCharacters(_ value: String) -> Bool {
        !value.unicodeScalars.contains {
            $0.value < 0x20 || $0.value == 0x7f
        }
    }
}
