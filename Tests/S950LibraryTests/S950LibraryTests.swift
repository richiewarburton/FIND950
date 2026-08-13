import Foundation
import XCTest
@testable import S950Library

final class S950LibraryTests: XCTestCase {
    func testCachedReclassificationPreservesS9SampleRateAndP9References() {
        let image = S950ImageCatalog(
            imageURL: URL(fileURLWithPath: "/tmp/rates.img"),
            name: "rates.img",
            volumes: [
                S950VolumeCatalog(
                    name: "VOLUME 001",
                    path: "/disk0/A/VOLUME 001",
                    entries: [
                        S950LibraryEntry(
                            index: 1,
                            name: "TONE.S9",
                            byteSize: 1_024,
                            kind: .other,
                            sampleRate: 44_100
                        ),
                        S950LibraryEntry(
                            index: 2,
                            name: "PATCH.P9",
                            byteSize: 128,
                            kind: .other,
                            sampleReferences: ["TONE"]
                        )
                    ]
                )
            ]
        )

        let reclassified = S950LibraryIndexDocument.reclassified(image)
        XCTAssertEqual(reclassified.volumes[0].entries[0].kind, .sample)
        XCTAssertEqual(reclassified.volumes[0].entries[0].sampleRate, 44_100)
        XCTAssertEqual(reclassified.volumes[0].entries[1].kind, .program)
        XCTAssertEqual(reclassified.volumes[0].entries[1].sampleReferences, ["TONE"])
    }

    func testCollectionHandoffDeduplicatesSourcesAndCarriesExactNativeIdentities() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "collection-handoff-test-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let source = temporary.appendingPathComponent("SOURCE.img")
        try Data([0x95, 0x00]).write(to: source)
        let handoff = try S950CollectionTransfer().prepareHandoff(
            selections: [
                .init(
                    sourceImage: source,
                    volumePath: "/disk0/A/VOLUME 001",
                    entry: .init(
                        index: 2,
                        name: "TONE.S9",
                        byteSize: 1_024,
                        kind: .sample
                    )
                ),
                .init(
                    sourceImage: source,
                    volumePath: "/disk0/A/VOLUME 001",
                    entry: .init(
                        index: 7,
                        name: "PATCH.P9",
                        byteSize: 128,
                        kind: .program
                    )
                )
            ],
            handoffRoot: temporary.appendingPathComponent("handoffs")
        )
        defer { handoff.cleanup() }

        XCTAssertEqual(handoff.request.messageType, "aim.export-collection.request")
        XCTAssertEqual(handoff.request.sources.count, 1)
        XCTAssertEqual(handoff.request.items.map(\.sourceIndex), [0, 0])
        XCTAssertEqual(handoff.request.items.map(\.directoryIndex), [2, 7])
        XCTAssertEqual(handoff.request.items.map(\.kind), ["sample", "program"])
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: handoff.requestURL))
                as? [String: Any]
        )
        XCTAssertNil(object["destination"])
        XCTAssertNil(object["density"])
        XCTAssertNil(object["writeMode"])
    }

    func testSharedTagsCoverIMGProgramAndSampleTargetsAcrossStoreInstances() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shared-tags-test-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let image = temporary.appendingPathComponent("Archive.img")
        let firstStore = SharedTagLibrary(directoryURL: temporary)
        let secondStore = SharedTagLibrary(directoryURL: temporary)
        _ = try firstStore.bootstrap()
        let drums = LibraryTag(name: "Drums", colorHex: "#FF5500")
        let favourite = LibraryTag(name: "Favourite", colorHex: "#00AAFF")
        _ = try firstStore.update { document in
            document.tags = [drums, favourite]
            document.set(true, tagID: drums.id, for: .image(image))
            document.set(
                true,
                tagID: favourite.id,
                for: .entry(
                    imageURL: image,
                    volumePath: "/disk0/A/BREAKS",
                    kind: .program,
                    filename: "AMEN.P9"
                )
            )
        }
        _ = try secondStore.update { document in
            document.set(
                true,
                tagID: drums.id,
                for: .entry(
                    imageURL: image,
                    volumePath: "/disk0/A/BREAKS",
                    kind: .sample,
                    filename: "amen.s9"
                )
            )
        }

        let loaded = try firstStore.load()
        XCTAssertEqual(loaded.tags(for: .image(image)), [drums])
        XCTAssertEqual(
            loaded.tags(for: .entry(
                imageURL: image,
                volumePath: "/disk0/A/BREAKS/",
                kind: .program,
                filename: "amen.p9"
            )),
            [favourite]
        )
        XCTAssertEqual(
            loaded.tags(for: .entry(
                imageURL: image,
                volumePath: "/disk0/A/BREAKS",
                kind: .sample,
                filename: "AMEN.S9"
            )),
            [drums]
        )
    }

    func testSharedTagsMigrateFIND950LegacyAssignmentsAndFollowRename() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shared-tags-migration-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let image = temporary.appendingPathComponent("Archive.img")
        let tag = LibraryTag(name: "Break", colorHex: "#AA33CC")
        let legacy = SharedTagDocument(
            schemaVersion: 1,
            tags: [tag],
            assignments: [
                "\(image.path)|/disk0/A/BREAKS|7|AMEN.S9": [tag.id]
            ]
        )
        let legacyURL = temporary.appendingPathComponent("metadata.json")
        try JSONEncoder().encode(legacy).write(to: legacyURL)
        let store = SharedTagLibrary(directoryURL: temporary)
        var loaded = try store.bootstrap(legacyMetadataURL: legacyURL)
        let source = SharedTagTarget.entry(
            imageURL: image,
            volumePath: "/disk0/A/BREAKS",
            kind: .sample,
            filename: "AMEN.S9"
        )
        let destination = SharedTagTarget.entry(
            imageURL: image,
            volumePath: "/disk0/A/BREAKS",
            kind: .sample,
            filename: "AMEN2.S9"
        )
        XCTAssertEqual(loaded.tags(for: source), [tag])

        loaded = try store.update { $0.moveAssignments(from: source, to: destination) }
        XCTAssertTrue(loaded.tags(for: source).isEmpty)
        XCTAssertEqual(loaded.tags(for: destination), [tag])
    }

    func testSharedTagIndexExportsAndRelocatesWithoutDeletingPreviousCopy() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "shared-tag-location-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: temporary) }
        let sourceDirectory = temporary.appendingPathComponent("Source", isDirectory: true)
        let destinationDirectory = temporary.appendingPathComponent(
            "Destination",
            isDirectory: true
        )
        let exportURL = temporary.appendingPathComponent("950TOOLS-tags.json")
        let source = SharedTagLibrary(directoryURL: sourceDirectory)
        _ = try source.bootstrap()
        let tag = LibraryTag(name: "Archive", colorHex: "#22AA88")
        let expected = try source.update { $0.tags = [tag] }

        try source.export(to: exportURL)
        let exported = try JSONDecoder().decode(
            SharedTagDocument.self,
            from: Data(contentsOf: exportURL)
        )
        XCTAssertEqual(exported, expected)

        let relocated = try source.relocate(
            to: destinationDirectory,
            activateSharedLocation: false
        )
        XCTAssertEqual(try relocated.load(), expected)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.fileURL.path))
    }

    func testFocusedExportHandoffUsesProtocolV1AndHasNoDestinationAuthority() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "s950-handoff-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("Source.img")
        try Data((0..<255).map(UInt8.init)).write(to: source)
        let createdAt = Date(timeIntervalSince1970: 1_786_378_000)
        let program = S950LibraryEntry(
            index: 41,
            name: "PROGRAM.P9",
            byteSize: 108,
            kind: .program,
            sampleReferences: ["SAMPLE ONE", "SAMPLE_ONE"]
        )
        let sample = S950LibraryEntry(
            index: 3,
            name: "SAMPLE ONE.S9",
            byteSize: 132_360,
            kind: .sample
        )
        let transfer = S950ProgramTransfer()
        let first = try transfer.prepareHandoff(
            sourceImage: source,
            sourceVolumePath: "/disk0/A/VOLUME 001",
            program: program,
            sourceEntries: [sample, program],
            createdAt: createdAt,
            handoffRoot: temporary.appendingPathComponent("first")
        )
        let second = try transfer.prepareHandoff(
            sourceImage: source,
            sourceVolumePath: "/disk0/A/VOLUME 001",
            program: program,
            sourceEntries: [sample, program],
            createdAt: createdAt,
            handoffRoot: temporary.appendingPathComponent("second")
        )
        XCTAssertEqual(first.request.requestID, second.request.requestID)
        XCTAssertEqual(first.request.messageType, "aim.export-program.request")
        XCTAssertEqual(first.request.source.sha256, try Tools950Protocol.sha256(of: source))
        XCTAssertEqual(first.request.program.directoryIndex, 41)
        XCTAssertEqual(first.request.observedDependencies.count, 1)
        XCTAssertEqual(first.request.observedDependencies.first?.directoryIndex, 3)
        XCTAssertEqual(first.request.observedDependencies.first?.filename, "SAMPLE ONE.S9")
        XCTAssertEqual(first.requestURL.pathExtension, Tools950Protocol.requestExtension)
        XCTAssertEqual(
            first.responseURL.deletingLastPathComponent(),
            first.requestURL.deletingLastPathComponent()
        )
        let encoded = try Data(contentsOf: first.requestURL)
        XCTAssertLessThanOrEqual(encoded.count, Tools950Protocol.maximumDocumentBytes)
        let decoded = try Tools950Protocol.decoder().decode(
            Tools950Protocol.ExportProgramRequest.self,
            from: encoded
        )
        XCTAssertEqual(decoded.requestID, first.request.requestID)
        XCTAssertEqual(decoded.source.path, first.request.source.path)
        XCTAssertEqual(decoded.source.sha256, first.request.source.sha256)
        XCTAssertEqual(decoded.program, first.request.program)
        XCTAssertEqual(decoded.observedDependencies, first.request.observedDependencies)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("destination"))
        first.cleanup()
        second.cleanup()
    }

    func testHandoffWaitsForAcceptedThenTerminalAndCleansArtifacts() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "s950-response-test-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let source = temporary.appendingPathComponent("Source.img")
        try Data(repeating: 1, count: 32).write(to: source)
        let program = S950LibraryEntry(index: 1, name: "TEST.P9", byteSize: 108, kind: .program)
        let transfer = S950ProgramTransfer()
        let handoff = try transfer.prepareHandoff(
            sourceImage: source,
            sourceVolumePath: "/disk0/A/VOLUME 001",
            program: program,
            sourceEntries: [program],
            handoffRoot: temporary.appendingPathComponent("handoff")
        )
        let acceptedResponse = Tools950Protocol.OperationResponse(
            protocolIdentifier: Tools950Protocol.protocolIdentifier,
            protocolVersion: 1,
            messageType: "operation.response",
            requestID: handoff.request.requestID,
            createdAt: Date(),
            sender: .init(productID: "com.e45recordings.EDIT950", version: "1.8.17", build: "34"),
            status: .accepted,
            operationType: "aim.export-program",
            summary: "Accepted",
            errorCode: nil,
            details: nil,
            result: nil
        )
        let rejectedResponse = Tools950Protocol.OperationResponse(
            protocolIdentifier: Tools950Protocol.protocolIdentifier,
            protocolVersion: 1,
            messageType: "operation.response",
            requestID: handoff.request.requestID,
            createdAt: Date(),
            sender: .init(productID: "com.e45recordings.EDIT950", version: "1.8.17", build: "34"),
            status: .rejected,
            operationType: "aim.export-program",
            summary: "Rejected for test",
            errorCode: "testRejection",
            details: nil,
            result: nil
        )
        let writer = Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            try Tools950Protocol.encoder().encode(acceptedResponse)
                .write(to: handoff.responseURL, options: .atomic)
            try await Task.sleep(nanoseconds: 150_000_000)
            try Tools950Protocol.encoder().encode(rejectedResponse)
                .write(to: handoff.responseURL, options: .atomic)
        }
        let acceptedExpectation = expectation(description: "accepted callback")
        let terminal = try await transfer.waitForTerminalResponse(
            to: handoff,
            acknowledgementTimeout: 2,
            pollIntervalNanoseconds: 20_000_000,
            onAccepted: { response in
                XCTAssertEqual(response.status, .accepted)
                acceptedExpectation.fulfill()
            }
        )
        try await writer.value
        await fulfillment(of: [acceptedExpectation], timeout: 1)
        XCTAssertEqual(terminal.status, .rejected)
        XCTAssertEqual(terminal.errorCode, "testRejection")
        XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.artifactDirectory.path))
    }

    func testAkaiUtilSessionAlwaysUsesReadOnlyAndBlocksMutationVerbs() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "s950-readonly-session-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let image = temporary.appendingPathComponent("Archive.img")
        try Data(repeating: 0, count: 32).write(to: image)
        let log = temporary.appendingPathComponent("commands.log")
        let helper = temporary.appendingPathComponent("fake-akaiutil")
        let script = """
        #!/bin/sh
        printf 'ARGS:%s\\n' "$*" >> '\(log.path)'
        printf '/disk0/A/VOLUME 001 > '
        while IFS= read -r command; do
          printf 'COMMAND:%s\\n' "$command" >> '\(log.path)'
          case "$command" in
            dir) printf '\\n/disk0/A/VOLUME 001 > ' ;;
            q) exit 0 ;;
          esac
        done
        """
        try script.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let session = AkaiUtilSession()
        try await session.open(imageURL: image, helperURL: helper)
        do {
            _ = try await session.send("put FORBIDDEN.S9")
            XCTFail("Mutating put command was not blocked")
        } catch let error as S950LibraryError {
            guard case .readOnlyCommandRequired("put") = error else {
                return XCTFail("Unexpected command error: \(error)")
            }
        }
        _ = try await session.send("dir")
        await session.close()
        let logText = try String(contentsOf: log)
        XCTAssertTrue(logText.contains("ARGS:-r"))
        XCTAssertTrue(logText.contains("COMMAND:dir"))
        XCTAssertFalse(logText.contains("COMMAND:put"))
    }

    func testIncrementalIndexReusesUnchangedImagesAndRefreshesOnlyChanges() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(
            "s950-index-cache-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let firstImage = temporary.appendingPathComponent("First.img")
        let secondImage = temporary.appendingPathComponent("Second.img")
        let brokenImage = temporary.appendingPathComponent("Broken.img")
        try Data(repeating: 1, count: 32).write(to: firstImage)
        try Data(repeating: 2, count: 32).write(to: secondImage)
        try Data().write(to: brokenImage)

        let coreHelper = temporary.appendingPathComponent("fake-akaiutil-core")
        try fakeHelper.write(to: coreHelper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: coreHelper.path
        )
        let launchLog = temporary.appendingPathComponent("launches.log")
        let helper = temporary.appendingPathComponent("fake-akaiutil")
        let wrapper = """
        #!/bin/sh
        printf 'launch\\n' >> '\(launchLog.path)'
        exec '\(coreHelper.path)' "$@"
        """
        try wrapper.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helper.path
        )

        let scanner = S950LibraryScanner(helperURL: helper)
        let initial = await scanner.scanIncrementally(
            folderURLs: [temporary],
            cached: S950LibraryIndexDocument()
        )
        XCTAssertEqual(initial.inspectedImageCount, 2)
        XCTAssertEqual(initial.reusedImageCount, 0)
        XCTAssertEqual(initial.collection.images.count, 2)
        XCTAssertEqual(
            initial.collection.failures.map { $0.imageURL.resolvingSymlinksInPath() },
            [brokenImage.resolvingSymlinksInPath()]
        )
        XCTAssertEqual(try launchCount(in: launchLog), 2)

        let cacheURL = temporary.appendingPathComponent("cache/index.json")
        try initial.index.write(to: cacheURL)
        let loaded = S950LibraryIndexDocument.load(from: cacheURL)
        XCTAssertEqual(loaded, initial.index)
        XCTAssertEqual(loaded.cachedCollection(folderURLs: [temporary]).images.count, 2)

        let unchanged = await scanner.scanIncrementally(
            folderURLs: [temporary],
            cached: loaded
        )
        XCTAssertEqual(unchanged.inspectedImageCount, 0)
        XCTAssertEqual(unchanged.reusedImageCount, 2)
        XCTAssertEqual(try launchCount(in: launchLog), 2)

        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: firstImage.path
        )
        let changed = await scanner.scanIncrementally(
            folderURLs: [temporary],
            cached: unchanged.index
        )
        XCTAssertEqual(changed.inspectedImageCount, 1)
        XCTAssertEqual(changed.reusedImageCount, 1)
        XCTAssertEqual(try launchCount(in: launchLog), 3)

        try FileManager.default.removeItem(at: secondImage)
        let removed = await scanner.scanIncrementally(
            folderURLs: [temporary],
            cached: changed.index
        )
        XCTAssertEqual(removed.inspectedImageCount, 0)
        XCTAssertEqual(removed.reusedImageCount, 1)
        XCTAssertEqual(removed.collection.images.map(\.name), ["First"])
        XCTAssertEqual(removed.index.records.count, 1)
        XCTAssertEqual(try launchCount(in: launchLog), 3)
    }

    func testParsesProgramsAndSamplesWithSpaces() {
        let listing = """
        /disk0/A/VOLUME 001
        fnr  fname               size/B  startblk  uncompr
        --------------------------------------------------
          1  KICK.S               16384   0x0004     -
         12  LONG SAMPLE.S        32768   0x0014   65536
         64  PROGRAM ONE.P9        2048   0x0024
        --------------------------------------------------
        total:   3 file(s) (max.  64),     51200 bytes

        /disk0/A/VOLUME 001 > 
        """

        let entries = AkaiOutputParser.directory(from: listing)
        XCTAssertEqual(entries.map(\.name), ["KICK.S", "LONG SAMPLE.S", "PROGRAM ONE.P9"])
        XCTAssertEqual(entries.map(\.kind), [.sample, .sample, .program])
    }

    func testFindsUniqueVolumePaths() {
        let listing = """
        /disk0/A/VOLUME 001
        /disk0/A/VOLUME 001 >
        /disk0/A/VOLUME 002
        /disk0/A/VOLUME 002 >
        """
        XCTAssertEqual(AkaiOutputParser.volumes(from: listing), [
            "/disk0/A/VOLUME 001", "/disk0/A/VOLUME 002"
        ])
    }

    func testScansFolderReadOnlyWithFakeHelper() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let image = temporary.appendingPathComponent("Old Breaks.IMG")
        try Data(repeating: 0, count: 32).write(to: image)
        let helper = temporary.appendingPathComponent("fake-akaiutil")
        try fakeHelper.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let result = try await S950LibraryScanner(helperURL: helper).scan(folderURL: temporary)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.images.first?.name, "Old Breaks")
        XCTAssertEqual(result.images.first?.programCount, 1)
        XCTAssertEqual(result.images.first?.sampleCount, 2)
        XCTAssertEqual(result.images.first?.volumes.first?.programs.first?.name, "JUNGLE.P9")
    }

    func testIncrementalScanRetainsCachedImagesWhenConfiguredMediaIsOffline() async {
        let missingFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let imageURL = missingFolder.appendingPathComponent("REMOVABLE.IMG")
        let catalog = S950ImageCatalog(
            imageURL: imageURL,
            name: "REMOVABLE",
            volumes: [],
            libraryFolderURL: missingFolder
        )
        let record = S950LibraryIndexRecord(
            signature: S950ImageIndexSignature(
                canonicalPath: imageURL.path,
                byteSize: 1_440_000,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            catalog: catalog
        )

        let result = await S950LibraryScanner(
            helperURL: URL(fileURLWithPath: "/helper-is-not-needed-for-offline-media")
        ).scanIncrementally(
            folderURLs: [missingFolder],
            cached: S950LibraryIndexDocument(records: [record])
        )

        XCTAssertEqual(result.index.records, [record])
        XCTAssertEqual(result.collection.images, [catalog])
        XCTAssertEqual(result.collection.failures.count, 1)
        XCTAssertEqual(result.inspectedImageCount, 0)
        XCTAssertEqual(result.reusedImageCount, 0)
    }

    func testCombinesMoreThanOneLibraryFolder() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = temporary.appendingPathComponent("First", isDirectory: true)
        let second = temporary.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data(repeating: 1, count: 32).write(to: first.appendingPathComponent("Drums.img"))
        try Data(repeating: 2, count: 32).write(to: second.appendingPathComponent("Bass.img"))
        let helper = temporary.appendingPathComponent("fake-akaiutil")
        try fakeHelper.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)

        let result = await S950LibraryScanner(helperURL: helper).scan(folderURLs: [first, second])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.images.map(\.name), ["Bass", "Drums"])
    }

    func testAuditionExportUsesTemporaryFolderWithoutChangingImage() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let exportFolder = URL(fileURLWithPath: "/tmp/s950-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: exportFolder)
        }
        let original = Data((0..<64).map(UInt8.init))
        let image = temporary.appendingPathComponent("Archive.img")
        try original.write(to: image)
        let helper = temporary.appendingPathComponent("fake-akaiutil")
        try fakeHelper.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        let sample = S950LibraryEntry(index: 1, name: "BREAK.S", byteSize: 16_384, kind: .sample)

        let wav = try await S950LibraryScanner(helperURL: helper).exportSampleForAudition(
            imageURL: image,
            volumePath: "/disk0/A/VOLUME 001",
            sample: sample,
            destinationFolder: exportFolder
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: wav.path))
        XCTAssertEqual(try Data(contentsOf: image), original)
    }

    func testReadsUniqueSampleReferencesFromP9Keygroups() throws {
        var data = Data(repeating: 0x20, count: 0x26 + 2 * 0x46)
        data[0x17] = 2
        write("AMEN", into: &data, at: 0x26 + 0x18)
        write("GHOST", into: &data, at: 0x26 + 0x2e)
        write("AMEN", into: &data, at: 0x26 + 0x46 + 0x18)
        write("2 SAMPLE", into: &data, at: 0x26 + 0x46 + 0x2e)

        XCTAssertEqual(try P9ReferenceParser.sampleNames(in: data), ["AMEN", "GHOST"])
    }

    func testNativeFilenameIdentityTreatsSpacesAndUnderscoresAsEquivalent() {
        XCTAssertEqual(
            P9ReferenceParser.nativeFilenameKey("BASS_DRUM.S9"),
            P9ReferenceParser.nativeFilenameKey("bass drum.s9")
        )
        XCTAssertNotEqual(
            P9ReferenceParser.nativeFilenameKey("BASS_DRUM.S9"),
            P9ReferenceParser.nativeFilenameKey("BASS DRUM.P9")
        )
    }

    func testReadsS9SampleRateFromNativeHeader() {
        var data = Data(repeating: 0, count: 0x3C)
        data[0x14] = 0x44
        data[0x15] = 0xAC

        XCTAssertEqual(S9MetadataParser.sampleRate(in: data), 44_100)
        XCTAssertNil(S9MetadataParser.sampleRate(in: Data(repeating: 0, count: 12)))
    }

    func testRemovableMediaCleanupDefaultsMatchSupportedMetadataNames() {
        XCTAssertEqual(RemovableMediaCleanupPolicy.defaultNames, [
            ".DS_Store", "._*", "._AppleDouble", ".AppleDouble", ".fseventsd",
            ".VolumeIcon.icns", ".TemporaryItems", ".DocumentRevisions-V100",
            ".Spotlight-V100", ".Trashes", ".localized", ".AppleDB", ".apdisk",
            "Thumbs.db", "Desktop.ini", ".syncing_db", ".Trash",
            ".metadata_never_index", ".bzvol", ".dbxignore",
            "System Volume Information", "$RECYCLE.BIN", "RECYCLED"
        ])
        XCTAssertEqual(
            RemovableMediaCleanupPolicy().activeNames.count,
            RemovableMediaCleanupPolicy.defaultNames.count
        )
    }

    func testRemovableMediaCleanupSupportsCustomNamesAndExceptions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("Samples", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let rootMetadata = root.appendingPathComponent(".DS_Store")
        let nestedMetadata = nested.appendingPathComponent("Thumbs.db")
        let keptMetadata = nested.appendingPathComponent("Desktop.ini")
        let custom = nested.appendingPathComponent("SAMPLER.CACHE")
        let appleDouble = nested.appendingPathComponent("._beat-disk.img")
        let similarlyNamed = nested.appendingPathComponent("Thumbs.db.backup")
        for url in [rootMetadata, nestedMetadata, keptMetadata, custom, appleDouble, similarlyNamed] {
            try Data([0x01]).write(to: url)
        }

        var policy = RemovableMediaCleanupPolicy()
        try policy.addCustomName("SAMPLER.CACHE")
        try policy.addException("Samples/Desktop.ini")
        let candidates = try RemovableMediaCleaner.candidates(on: root, policy: policy)

        XCTAssertEqual(Set(candidates.map(\.relativePath)), [
            ".DS_Store", "Samples/Thumbs.db", "Samples/SAMPLER.CACHE",
            "Samples/._beat-disk.img"
        ])
        let result = try RemovableMediaCleaner.remove(candidates, from: root)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(Set(result.removedPaths), Set(candidates.map(\.relativePath)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rootMetadata.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: nestedMetadata.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: custom.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: appleDouble.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: keptMetadata.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: similarlyNamed.path))
        XCTAssertTrue(
            try RemovableMediaCleaner.candidates(
                on: root,
                policy: policy
            ).isEmpty
        )
    }

    func testIncompleteCleanupInspectionDirectsUserToFullDiskAccess() {
        let description = RemovableMediaCleanupError
            .enumerationFailed("/Volumes/AKAI/.Spotlight-V100")
            .errorDescription ?? ""
        XCTAssertTrue(description.contains("Full Disk Access"))
    }

    func testCleanupExceptionInsideMatchedDirectoryPreservesTheDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let trash = root.appendingPathComponent(".Trashes", isDirectory: true)
        let kept = trash.appendingPathComponent("Keep Me.txt")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data([0x01]).write(to: kept)
        defer { try? FileManager.default.removeItem(at: root) }

        var policy = RemovableMediaCleanupPolicy()
        try policy.addException(".Trashes/Keep Me.txt")
        let candidates = try RemovableMediaCleaner.candidates(on: root, policy: policy)

        XCTAssertFalse(candidates.contains { $0.relativePath == ".Trashes" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
    }

    func testPartialCleanupReportsFailedTargetsAndKeepsSuccessfulRemovals() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try Data([0x01]).write(to: outside)
        let removable = root.appendingPathComponent(".DS_Store")
        try Data([0x01]).write(to: removable)
        let candidates = [
            RemovableMediaCleanupCandidate(
                url: outside,
                relativePath: ".Spotlight-V100",
                isDirectory: true
            ),
            RemovableMediaCleanupCandidate(
                url: removable,
                relativePath: ".DS_Store",
                isDirectory: false
            )
        ]

        let result = try RemovableMediaCleaner.remove(candidates, from: root)

        XCTAssertEqual(result.removedPaths, [".DS_Store"])
        XCTAssertEqual(result.failures.map(\.relativePath), [
            ".Spotlight-V100"
        ])
        XCTAssertFalse(FileManager.default.fileExists(atPath: removable.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    private func write(_ value: String, into data: inout Data, at offset: Int) {
        for (index, byte) in value.utf8.prefix(10).enumerated() {
            data[offset + index] = byte
        }
    }

    private func launchCount(in url: URL) throws -> Int {
        try String(contentsOf: url)
            .split(whereSeparator: \.isNewline)
            .count
    }

    private let fakeHelper = #"""
    #!/bin/sh
    destination=''
    printf '/disk0/A/VOLUME 001 > '
    while IFS= read -r command; do
      case "$command" in
        dirrec)
          printf '\n/disk0/A/VOLUME 001\n/disk0/A/VOLUME 001 > '
          ;;
        cd*)
          printf '\n/disk0/A/VOLUME 001 > '
          ;;
        lcd*)
          destination=${command#lcd }
          printf '\n/disk0/A/VOLUME 001 > '
          ;;
        sample2wavi*)
          : > "$destination/AUDITION.wav"
          printf '\n/disk0/A/VOLUME 001 > '
          ;;
        geti*)
          : > "$destination/JUNGLE.P9"
          printf '\n/disk0/A/VOLUME 001 > '
          ;;
        dir)
          printf '\n/disk0/A/VOLUME 001\n  1  BREAK.S  16384  0x0004  -\n  2  BASS.S  8192  0x0014  -\n  3  JUNGLE.P9  2048  0x0024\n/disk0/A/VOLUME 001 > '
          ;;
        q)
          exit 0
          ;;
      esac
    done
    """#
}
