import AppKit
@preconcurrency import AVFoundation
import S950Library
import SwiftUI
import UniformTypeIdentifiers

private enum BundledAkaiUtil {
    static func locate() throws -> URL {
        let resources = Bundle.main.resourceURL
            ?? Bundle.main.bundleURL.appendingPathComponent(
                "Contents/Resources",
                isDirectory: true
            )
        let helper = resources.appendingPathComponent("akaiutil", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw BundledAkaiUtilError.unavailable
        }
        return helper
    }
}

private enum BundledAkaiUtilError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "FIND950 is incomplete because its included AKAI Util helper is missing or damaged. Reinstall FIND950."
    }
}

@main
struct FIND950App: App {
    @StateObject private var model = Find950Model()
    @StateObject private var undoHistory = SuiteUndoCoordinator()
    @StateObject private var suitePreferences = SuitePreferences(
        app: .find,
        defaultInspectorVisible: true
    )
    @StateObject private var releaseChecker: GitHubReleaseChecker
    @State private var showAbout = false

    init() {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "DEV"
        _releaseChecker = StateObject(wrappedValue: GitHubReleaseChecker(
            product: "FIND950",
            owner: "richiewarburton",
            repository: "FIND950",
            currentVersion: version
        ))
        SuiteFontGate.validateBundle()
    }

    var body: some Scene {
        WindowGroup("FIND950") {
            VStack(spacing: 0) {
                SuiteUpdateBanner(checker: releaseChecker)
                SuiteZoomContainer {
                    Find950View(model: model)
                        .suiteSurface()
                }
                if model.isLogVisible {
                    Divider()
                    FindDiagnosticLogView(model: model)
                        .frame(minHeight: 120, idealHeight: 190, maxHeight: 280)
                }
            }
            .background(Color.suiteBackground)
            .environmentObject(suitePreferences)
            .preferredColorScheme(suitePreferences.appearance.colorScheme)
            .onAppear { model.undoManager = undoHistory.manager }
            .task { await releaseChecker.startAutomaticCheck() }
            .frame(minWidth: 880, minHeight: 520)
            .sheet(isPresented: $showAbout) {
                SuiteAboutView(
                    product: "FIND950",
                    version: releaseChecker.currentVersion
                )
            }
            .sheet(isPresented: $releaseChecker.isPresentingResult) {
                SuiteUpdateResultView(checker: releaseChecker)
            }
        }
        .defaultSize(width: 1240, height: 760)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button(undoHistory.undoTitle) { undoHistory.undo() }
                    .keyboardShortcut("z")
                    .disabled(!undoHistory.canUndo)
                Button(undoHistory.redoTitle) { undoHistory.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!undoHistory.canRedo)
            }
            CommandGroup(replacing: .appInfo) {
                Button("ABOUT FIND950…") { showAbout = true }
                Divider()
                Button("CHECK FOR UPDATES…") {
                    Task { await releaseChecker.checkForUpdates(presentResult: true) }
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add IMG Folders…") { model.addFolders() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") { model.requestSearchFocus() }
                    .keyboardShortcut("f")
            }
            CommandMenu("Audition") {
                Button("Audition Selected Sample") {
                    _ = model.handleSpaceForSelectedEntry()
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            CommandMenu("Diagnostics") {
                Toggle("Show Diagnostic Log", isOn: $model.isLogVisible)
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("Save Diagnostic Log…") { model.saveDiagnosticLog() }
                Button("Reveal Live Log in Finder") { model.revealDiagnosticLog() }
            }
            CommandGroup(replacing: .sidebar) {
                Button(
                    suitePreferences.sidebarVisible
                        ? "Hide Folders Sidebar" : "Show Folders Sidebar"
                ) {
                    suitePreferences.sidebarVisible.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button(
                    suitePreferences.inspectorVisible
                        ? "Hide Metadata, Tags & Actions"
                        : "Show Metadata, Tags & Actions"
                ) {
                    suitePreferences.inspectorVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
                Button(
                    suitePreferences.collectionVisible
                        ? "Hide Collection Pane" : "Show Collection Pane"
                ) {
                    suitePreferences.collectionVisible.toggle()
                }
                Divider()
                Menu("Appearance") {
                    ForEach(SuiteAppearance.allCases) { appearance in
                        Button {
                            suitePreferences.appearance = appearance
                        } label: {
                            if suitePreferences.appearance == appearance {
                                Label(appearance.title, systemImage: "checkmark")
                            } else {
                                Text(appearance.title)
                            }
                        }
                    }
                }
                Divider()
                Button("Zoom Out") { suitePreferences.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(suitePreferences.zoom == .fifty)
                Button("Actual Size") { suitePreferences.zoom = .oneHundred }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Zoom In") { suitePreferences.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(suitePreferences.zoom == .twoHundred)
                Divider()
                ForEach(SuiteZoomLevel.allCases) { zoom in
                    Button {
                        suitePreferences.zoom = zoom
                    } label: {
                        if suitePreferences.zoom == zoom {
                            Label(zoom.title, systemImage: "checkmark")
                        } else {
                            Text(zoom.title)
                        }
                    }
                }
            }
        }
        Settings {
            LibrarySettingsView(model: model)
                .environmentObject(suitePreferences)
                .preferredColorScheme(suitePreferences.appearance.colorScheme)
                .suiteSurface()
        }
    }
}

enum LibrarySearchScope: String, CaseIterable, Identifiable {
    case selectedDisk = "Selected Disk"
    case entireLibrary = "Entire Library"
    var id: String { rawValue }
}

struct LibrarySearchResult: Identifiable {
    let image: S950ImageCatalog
    let volume: S950VolumeCatalog
    let entry: S950LibraryEntry
    var id: String { "\(image.imageURL.path)|\(volume.path)|\(entry.id)" }
}

struct FindCollectionManifest {
    // A freshly formatted S950 high-density image reports 0x063b free
    // 0x0400-byte blocks. Native files consume whole allocation blocks.
    static let allocationBlockBytes: Int64 = 1_024
    static let highDensityUsableBytes: Int64 = 1_595 * allocationBlockBytes
    static let maximumFileCount = 64

    let explicitEntries: [LibrarySearchResult]
    let exportEntries: [LibrarySearchResult]
    let filenameCollisions: [String]

    var totalBytes: Int64 {
        exportEntries.reduce(0) { total, item in
            let size = max(0, item.entry.byteSize)
            let blocks = (size + Self.allocationBlockBytes - 1)
                / Self.allocationBlockBytes
            return total + blocks * Self.allocationBlockBytes
        }
    }

    var fileCount: Int { exportEntries.count }
    var remainingBytes: Int64 {
        max(0, Self.highDensityUsableBytes - totalBytes)
    }
    var storageFraction: Double {
        Double(totalBytes) / Double(Self.highDensityUsableBytes)
    }
    var directoryFraction: Double {
        Double(fileCount) / Double(Self.maximumFileCount)
    }
    var limitingFraction: Double { max(storageFraction, directoryFraction) }
    var canExport: Bool {
        !exportEntries.isEmpty
            && totalBytes <= Self.highDensityUsableBytes
            && fileCount <= Self.maximumFileCount
            && filenameCollisions.isEmpty
    }

    var exportBlockers: [String] {
        var blockers: [String] = []
        if exportEntries.isEmpty {
            blockers.append("Collect at least one P9 program or S9 sample.")
        }
        if totalBytes > Self.highDensityUsableBytes {
            blockers.append(
                "The collection exceeds a fresh High Density IMG by "
                    + ByteCountFormatter.string(
                        fromByteCount: totalBytes - Self.highDensityUsableBytes,
                        countStyle: .file
                    ).uppercased()
                    + "."
            )
        }
        if fileCount > Self.maximumFileCount {
            blockers.append(
                "The collection needs \(fileCount) directory slots; a fresh IMG has "
                    + "\(Self.maximumFileCount)."
            )
        }
        if !filenameCollisions.isEmpty {
            blockers.append(
                "Native filename collisions: "
                    + filenameCollisions.joined(separator: ", ")
                    + ". Keep only one file for each native name."
            )
        }
        return blockers
    }
}

struct RelatedProgramsContext: Identifiable {
    let id = UUID()
    let image: S950ImageCatalog
    let volume: S950VolumeCatalog
    let sample: S950LibraryEntry
    let programs: [S950LibraryEntry]
}

struct BrowserNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct FindSafeEjectCleanupError: LocalizedError {
    let mediaName: String
    let detail: String

    var errorDescription: String? {
        "Safe Eject stopped because \(mediaName) could not be verified clean. The volume remains mounted.\n\n\(detail)\n\nGrant FIND950 Full Disk Access in System Settings → Privacy & Security → Full Disk Access, quit and reopen FIND950, then try again."
    }
}

@MainActor
final class Find950Model: ObservableObject {
    @Published private(set) var collection: S950LibraryCollection? {
        didSet {
            rebuildEntryLookup()
            invalidateCollectionCache()
        }
    }
    @Published private(set) var folderURLs: [URL]
    @Published var selectedImageID: URL? {
        didSet {
            guard selectedImageID != oldValue else { return }
            diagnostics.record(
                .info,
                category: "selection",
                message: "Selected IMG changed",
                fields: ["image": selectedImageID?.path ?? "none"]
            )
        }
    }
    @Published var selectedEntryIDs: Set<String> = [] {
        didSet {
            guard oldValue != selectedEntryIDs else { return }
            diagnostics.record(
                .debug,
                category: "selection",
                message: "Native-file selection changed",
                fields: ["count": String(selectedEntryIDs.count)]
            )
            if let primarySelectedEntryID,
               selectedEntryIDs.contains(primarySelectedEntryID) {
                return
            }
            primarySelectedEntryID = selectedEntryIDs.sorted().first
            guard let context = selectedEntryContext() else { return }
            selectedImageID = context.image.id
        }
    }
    @Published var searchText = ""
    @Published var searchScope: LibrarySearchScope = .selectedDisk {
        didSet {
            guard searchScope != oldValue else { return }
            diagnostics.record(
                .info,
                category: "search",
                message: "Search scope changed",
                fields: ["scope": searchScope.rawValue]
            )
        }
    }
    @Published private(set) var searchFocusRequest = 0
    @Published private(set) var mainPaneFocusRequest = 0
    @Published var selectedTagFilterID: UUID?
    @Published var showTagManager = false {
        didSet {
            guard showTagManager != oldValue else { return }
            diagnostics.record(
                .info,
                category: "dialogue",
                message: showTagManager ? "Tag manager presented" : "Tag manager dismissed"
            )
        }
    }
    @Published var relatedPrograms: RelatedProgramsContext? {
        didSet {
            guard relatedPrograms?.id != oldValue?.id else { return }
            diagnostics.record(
                .info,
                category: "dialogue",
                message: relatedPrograms == nil
                    ? "Related-programs dialogue dismissed"
                    : "Related-programs dialogue presented",
                fields: ["sample": relatedPrograms?.sample.name ?? "none"]
            )
        }
    }
    @Published private(set) var collectedEntryIDs: Set<String> {
        didSet { invalidateCollectionCache() }
    }
    @Published var notice: BrowserNotice? {
        didSet {
            if notice != nil, errorMessage != nil { errorMessage = nil }
            if let notice, notice.id != oldValue?.id {
                diagnostics.record(
                    .info,
                    category: "operation",
                    message: notice.title,
                    fields: ["detail": notice.message]
                )
            }
        }
    }
    @Published private(set) var isScanning = false
    @Published private(set) var isWorking = false
    @Published private(set) var collectionExportStatus: String?
    @Published private(set) var auditioningID: String?
    @Published private(set) var tags: [LibraryTag]
    @Published private(set) var tagAssignments: [String: Set<UUID>]
    @Published private(set) var hiddenFolderPaths: Set<String>
    @Published private(set) var libraryDataDirectoryURL: URL
    @Published private(set) var tagLibraryDirectoryURL: URL
    @Published private(set) var mediaVolumesByFolderPath: [String: FindMediaVolume] = [:]
    @Published private(set) var ejectingMediaIDs: Set<String> = []
    @Published var mediaCleanupPolicy = RemovableMediaCleanupPolicy() {
        didSet { persistMediaCleanupPolicy() }
    }
    @Published var errorMessage: String? {
        didSet {
            if errorMessage != nil, notice != nil { notice = nil }
            guard let errorMessage, errorMessage != oldValue else { return }
            diagnostics.record(
                .error,
                category: "operation",
                message: "Operation failed",
                fields: ["error": errorMessage]
            )
            if autoOpenDiagnosticLogOnError { isLogVisible = true }
        }
    }
    @Published var isLogVisible = false
    @Published var autoOpenDiagnosticLogOnError: Bool = UserDefaults.standard.object(
        forKey: "FIND950.autoOpenDiagnosticLogOnError"
    ) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(
                autoOpenDiagnosticLogOnError,
                forKey: "FIND950.autoOpenDiagnosticLogOnError"
            )
        }
    }

    weak var undoManager: UndoManager?
    let diagnostics = DiagnosticLogStore(appName: "FIND950")

    private let defaultsKey = "FIND950.folderPaths"
    private let hiddenFoldersDefaultsKey = "FIND950.excludedSearchFolderPaths"
    private let collectionDefaultsKey = "FIND950.collectedEntryIDs"
    private let mediaCleanupDefaultsKey = "FIND950.removableMediaCleanupPolicy"
    private let audition = SafeSampleAuditionController()
    private let volumeCoordination = VolumeCoordinationCenter(appName: "FIND950")
    private var edit950ApplicationURL: URL?
    private var indexCache: S950LibraryIndexDocument
    private var tagLibrary: SharedTagLibrary
    private var tagChangeObserver: NSObjectProtocol?
    private var workspaceMediaObservers: [NSObjectProtocol] = []
    private var scanPending = false
    private var primarySelectedEntryID: String?
    private var entryLookup: [String: LibrarySearchResult] = [:]
    private var cachedCollectedEntries: [LibrarySearchResult]?
    private var cachedCollectionManifest: FindCollectionManifest?

    var selectedEntryID: String? {
        get { primarySelectedEntryID }
        set {
            primarySelectedEntryID = newValue
            selectedEntryIDs = newValue.map { Set([$0]) } ?? []
        }
    }

    func selectImage(_ image: S950ImageCatalog) {
        guard selectedImageID != image.id || !selectedEntryIDs.isEmpty else {
            return
        }
        if !selectedEntryIDs.isEmpty {
            selectedEntryID = nil
        }
        if selectedImageID != image.id {
            selectedImageID = image.id
        }
    }

    var errorOffersFullDiskAccess: Bool {
        errorMessage?.localizedCaseInsensitiveContains("Full Disk Access") == true
    }

    func dismissNotice() {
        notice = nil
    }

    func dismissError() {
        errorMessage = nil
    }

    func copyDiagnosticLog() {
        diagnostics.record(
            .info,
            category: "diagnostics",
            message: "Log copied by user"
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnostics.text, forType: .string)
    }

    func saveDiagnosticLog() {
        let panel = NSSavePanel()
        panel.title = "Save FIND950 Diagnostic Log"
        panel.message = "The report contains the rolling activity timeline, app version and operation state. Home and temporary paths are shortened. It contains no sample audio or IMG data."
        panel.prompt = "Save Diagnostic Log"
        panel.nameFieldStringValue = "FIND950-diagnostic-\(Self.diagnosticFileStamp()).log"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        diagnostics.record(
            .info,
            category: "diagnostics",
            message: "Diagnostic log exported by user",
            fields: ["destination": destination.path]
        )
        do {
            try diagnostics.saveCopy(to: destination)
            notice = BrowserNotice(
                title: "Diagnostic Log Saved",
                message: "Saved a readable copy at \(destination.path)."
            )
        } catch {
            errorMessage = "Couldn’t save the diagnostic log: \(error.localizedDescription)"
        }
    }

    func revealDiagnosticLog() {
        diagnostics.record(
            .info,
            category: "diagnostics",
            message: "Live diagnostic log revealed in Finder"
        )
        NSWorkspace.shared.activateFileViewerSelecting([diagnostics.fileURL])
    }

    func clearDiagnosticLog() {
        diagnostics.clear()
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    init() {
        if let data = UserDefaults.standard.data(
            forKey: "FIND950.removableMediaCleanupPolicy"
        ), let policy = try? JSONDecoder().decode(
            RemovableMediaCleanupPolicy.self,
            from: data
        ) {
            mediaCleanupPolicy = policy
        }
        let initialDataDirectory = LibraryMetadataPersistence.directoryURL
        libraryDataDirectoryURL = initialDataDirectory
        let tagDirectory = SharedTagLibrary.resolvedDirectoryURL(
            preferredDirectoryURL: initialDataDirectory
        )
        tagLibraryDirectoryURL = tagDirectory
        let initialTagLibrary = SharedTagLibrary(directoryURL: tagDirectory)
        let metadata: SharedTagDocument
        var tagLoadError: String?
        do {
            metadata = try initialTagLibrary.bootstrap(
                legacyMetadataURL: LibraryMetadataPersistence
                    .legacyMetadataFileURL(in: initialDataDirectory)
            )
        } catch {
            metadata = SharedTagDocument()
            tagLoadError = "Couldn’t load shared library tags: \(error.localizedDescription)"
        }
        tagLibrary = initialTagLibrary
        tags = metadata.tags
        tagAssignments = metadata.assignments
        let legacyDefaults = UserDefaults(suiteName: "com.e45recordings.S950LibraryBrowser")
        let hiddenPaths = UserDefaults.standard.stringArray(forKey: hiddenFoldersDefaultsKey)
            ?? legacyDefaults?.stringArray(forKey: "S950LibraryBrowser.excludedSearchFolderPaths")
            ?? []
        hiddenFolderPaths = Set(hiddenPaths)
        collectedEntryIDs = Set(
            UserDefaults.standard.stringArray(forKey: collectionDefaultsKey) ?? []
        )
        let storedFolders = UserDefaults.standard.stringArray(forKey: defaultsKey)
            ?? legacyDefaults?.stringArray(forKey: "S950LibraryBrowser.folderPaths")
        let initialFolders = storedFolders?.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? []
        folderURLs = initialFolders
        let cachedIndex = S950LibraryIndexDocument.load(
            from: LibraryMetadataPersistence.indexFileURL(in: initialDataDirectory)
        )
        indexCache = cachedIndex
        let cachedCollection = cachedIndex.cachedCollection(folderURLs: initialFolders)
        collection = cachedCollection
        selectedImageID = cachedCollection.images.first { image in
            guard let folder = image.libraryFolderURL else { return true }
            return !hiddenFolderPaths.contains(folder.standardizedFileURL.path)
        }?.id
        errorMessage = tagLoadError
        refreshMediaVolumes()
        audition.onPlaybackEnded = { [weak self] in self?.auditioningID = nil }
        tagChangeObserver = DistributedNotificationCenter.default().addObserver(
            forName: SharedTagLibrary.distributedChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in model.reloadSharedTags() }
        }
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceMediaObservers.append(workspaceNotifications.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let model = self else { return }
            Task { @MainActor in
                model.refreshMediaVolumes()
                if !model.folderURLs.isEmpty { model.scanFolders() }
            }
        })
        for name in [NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            workspaceMediaObservers.append(workspaceNotifications.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let model = self else { return }
                Task { @MainActor in model.refreshMediaVolumes() }
            })
        }
        rebuildEntryLookup()
        diagnostics.record(
            .info,
            category: "lifecycle",
            message: "Library model ready",
            fields: [
                "folders": String(folderURLs.count),
                "cachedImages": String(collection?.images.count ?? 0),
                "cachedPrograms": String(
                    collection?.images.reduce(0) { $0 + $1.programCount } ?? 0
                ),
                "cachedSamples": String(
                    collection?.images.reduce(0) { $0 + $1.sampleCount } ?? 0
                )
            ]
        )
        if !folderURLs.isEmpty { scanFolders() }
    }

    deinit {
        if let tagChangeObserver {
            DistributedNotificationCenter.default().removeObserver(tagChangeObserver)
        }
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        for observer in workspaceMediaObservers {
            workspaceNotifications.removeObserver(observer)
        }
    }

    var allImages: [S950ImageCatalog] { collection?.images ?? [] }
    var visibleLibraryImages: [S950ImageCatalog] {
        allImages.filter { image in
            guard let folder = image.libraryFolderURL else { return true }
            return isFolderVisible(folder)
        }
    }
    var images: [S950ImageCatalog] {
        visibleLibraryImages.filter { image in
            imageHasSelectedTag(image)
        }
    }
    var selectedImage: S950ImageCatalog? { images.first { $0.id == selectedImageID } }
    var tagLibraryFileURL: URL {
        tagLibraryDirectoryURL.appendingPathComponent(SharedTagLibrary.filename)
    }
    var visibleFolderURLs: [URL] { folderURLs.filter(isFolderVisible) }
    var visibleProgramCount: Int {
        visibleLibraryImages.reduce(0) { $0 + $1.programCount }
    }
    var visibleSampleCount: Int {
        visibleLibraryImages.reduce(0) { $0 + $1.sampleCount }
    }

    var ejectableMediaVolumes: [FindMediaVolume] {
        let uniqueVolumes = Dictionary(
            mediaVolumesByFolderPath.values.map { ($0.id, $0) },
            uniquingKeysWith: { current, _ in current }
        )
        return uniqueVolumes.values
            .filter { $0.isAvailable && $0.isEjectable }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func mediaVolume(for folderURL: URL) -> FindMediaVolume? {
        mediaVolumesByFolderPath[folderURL.standardizedFileURL.path]
    }

    func mediaVolume(for image: S950ImageCatalog) -> FindMediaVolume? {
        if let folderURL = image.libraryFolderURL,
           let media = mediaVolume(for: folderURL) {
            return media
        }
        return mediaVolume(containing: image.imageURL)
    }

    func mediaStatus(for image: S950ImageCatalog) -> String {
        if let media = mediaVolume(for: image) { return media.kindTitle }
        return isImageAvailable(image) ? "LOCAL" : "MISSING"
    }

    func isImageAvailable(_ image: S950ImageCatalog) -> Bool {
        FileManager.default.fileExists(atPath: image.imageURL.standardizedFileURL.path)
    }

    func canEject(_ media: FindMediaVolume) -> Bool {
        media.isAvailable
            && media.isEjectable
            && !isScanning
            && !isWorking
            && !ejectingMediaIDs.contains(media.id)
    }

    func eject(_ media: FindMediaVolume) {
        guard canEject(media) else {
            if isScanning || isWorking {
                errorMessage = "Wait for FIND950 to finish its current disk operation before ejecting \(media.name)."
            } else if !media.isAvailable {
                errorMessage = "\(media.name) is already offline."
            } else {
                errorMessage = "macOS does not report \(media.name) as ejectable."
            }
            return
        }

        let ejectLease: VolumeEjectLease
        do {
            ejectLease = try volumeCoordination.beginEject(of: media.mountURL)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        diagnostics.record(
            .info,
            category: "safe-eject",
            message: "Safe eject requested",
            fields: [
                "media": media.name,
                "mount": media.mountURL.path
            ]
        )

        audition.stop()
        auditioningID = nil
        ejectingMediaIDs.insert(media.id)
        errorMessage = nil
        Task {
            defer { ejectLease.release() }
            var cleanupResult = RemovableMediaCleanupResult(
                removedPaths: [],
                failures: []
            )
            do {
                let policy = mediaCleanupPolicy
                let candidates = try await Task.detached(priority: .userInitiated) {
                    try RemovableMediaCleaner.candidates(
                        on: media.mountURL,
                        policy: policy
                    )
                }.value

                diagnostics.record(
                    .info,
                    category: "safe-eject",
                    message: "Cleanup inspection completed",
                    fields: [
                        "media": media.name,
                        "candidates": String(candidates.count)
                    ]
                )

                if !candidates.isEmpty {
                    switch confirmCleanup(candidates, media: media) {
                    case .cancel:
                        diagnostics.record(
                            .info,
                            category: "safe-eject",
                            message: "Safe eject cancelled at cleanup confirmation",
                            fields: ["media": media.name]
                        )
                        ejectingMediaIDs.remove(media.id)
                        return
                    case .cleanAndEject:
                        cleanupResult = try await Task.detached(priority: .userInitiated) {
                            try RemovableMediaCleaner.remove(
                                candidates,
                                from: media.mountURL
                            )
                        }.value
                    }
                }

                if !cleanupResult.failures.isEmpty {
                    let detail = cleanupResult.failures.prefix(20).map {
                        "\($0.relativePath): \($0.message)"
                    }.joined(separator: "\n")
                    throw FindSafeEjectCleanupError(
                        mediaName: media.name,
                        detail: detail
                    )
                }

                let remaining = try await Task.detached(priority: .userInitiated) {
                    try RemovableMediaCleaner.candidates(
                        on: media.mountURL,
                        policy: policy
                    )
                }.value
                guard remaining.isEmpty else {
                    let detail = remaining.prefix(20).map(\.relativePath)
                        .joined(separator: "\n")
                    throw FindSafeEjectCleanupError(
                        mediaName: media.name,
                        detail: "Still present after cleanup:\n\(detail)"
                    )
                }

                try await nativeEject(media)
                diagnostics.record(
                    .info,
                    category: "safe-eject",
                    message: "Media unmounted and ejected",
                    fields: [
                        "media": media.name,
                        "removedMetadataItems": String(cleanupResult.removedPaths.count)
                    ]
                )
                refreshMediaVolumes()
                notice = BrowserNotice(
                    title: cleanupResult.removedPaths.isEmpty
                        ? "Media Verified and Ejected" : "Media Cleaned and Ejected",
                    message: successfulEjectMessage(
                        cleanupResult: cleanupResult,
                        media: media
                    )
                )
            } catch {
                refreshMediaVolumes()
                errorMessage = "Couldn’t cleanly eject \(media.name): \(error.localizedDescription)"
            }
            ejectingMediaIDs.remove(media.id)
        }
    }

    private func successfulEjectMessage(
        cleanupResult: RemovableMediaCleanupResult,
        media: FindMediaVolume
    ) -> String {
        var details: [String] = []
        if !cleanupResult.removedPaths.isEmpty {
            details.append(
                "Removed \(cleanupResult.removedPaths.count) configured metadata item(s)."
            )
        }
        details.append("Verified that no configured metadata items remain.")
        details.append(
            "macOS cleanly unmounted and ejected \(media.name). Its cached catalogue remains searchable and will reconnect when the media returns."
        )
        return details.joined(separator: " ")
    }

    func setDefaultCleanupName(_ name: String, enabled: Bool) {
        var policy = mediaCleanupPolicy
        policy.setDefault(name, enabled: enabled)
        mediaCleanupPolicy = policy
    }

    func addCustomCleanupName(_ name: String) -> Bool {
        var policy = mediaCleanupPolicy
        do {
            try policy.addCustomName(name)
            mediaCleanupPolicy = policy
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeCustomCleanupName(_ name: String) {
        var policy = mediaCleanupPolicy
        policy.customNames.removeAll {
            $0.caseInsensitiveCompare(name) == .orderedSame
        }
        mediaCleanupPolicy = policy
    }

    func addCleanupException(_ exception: String) -> Bool {
        var policy = mediaCleanupPolicy
        do {
            try policy.addException(exception)
            mediaCleanupPolicy = policy
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func removeCleanupException(_ exception: String) {
        var policy = mediaCleanupPolicy
        policy.exceptions.removeAll {
            $0.caseInsensitiveCompare(exception) == .orderedSame
        }
        mediaCleanupPolicy = policy
    }

    func resetMediaCleanupPolicy() {
        mediaCleanupPolicy = RemovableMediaCleanupPolicy()
    }

    func refreshMediaVolumes() {
        var refreshed: [String: FindMediaVolume] = [:]
        for folderURL in folderURLs {
            let path = folderURL.standardizedFileURL.path
            if let mounted = FindMediaVolumeResolver.mountedVolume(containing: folderURL) {
                refreshed[path] = mounted
            } else if let previous = mediaVolumesByFolderPath[path] {
                refreshed[path] = previous.withAvailability(false)
            } else if let offline = FindMediaVolumeResolver.offlineVolumeHint(
                containing: folderURL
            ) {
                refreshed[path] = offline
            }
        }
        mediaVolumesByFolderPath = refreshed
    }

    private func mediaVolume(containing url: URL) -> FindMediaVolume? {
        let path = url.standardizedFileURL.path
        if let match = mediaVolumesByFolderPath
            .sorted(by: { $0.key.count > $1.key.count })
            .first(where: { path == $0.key || path.hasPrefix($0.key + "/") }) {
            return match.value
        }
        return FindMediaVolumeResolver.mountedVolume(containing: url)
            ?? FindMediaVolumeResolver.offlineVolumeHint(containing: url)
    }

    private func beginVolumeUse(
        for urls: [URL],
        detail: String
    ) throws -> [VolumeUseLease] {
        var volumesByPath: [String: URL] = [:]
        for media in urls.compactMap({
            FindMediaVolumeResolver.mountedVolume(containing: $0)
        }) {
            volumesByPath[media.mountURL.standardizedFileURL.path] = media.mountURL
        }
        let volumes = volumesByPath.values
        var leases: [VolumeUseLease] = []
        do {
            for volume in volumes {
                leases.append(
                    try volumeCoordination.beginUse(of: volume, detail: detail)
                )
            }
            return leases
        } catch {
            leases.forEach { $0.release() }
            throw error
        }
    }

    private func releaseVolumeUse(_ leases: [VolumeUseLease]) {
        leases.forEach { $0.release() }
    }

    private enum CleanupEjectDecision {
        case cleanAndEject
        case cancel
    }

    private func confirmCleanup(
        _ candidates: [RemovableMediaCleanupCandidate],
        media: FindMediaVolume
    ) -> CleanupEjectDecision {
        let preview = candidates.prefix(8).map { "• \($0.relativePath)" }
            .joined(separator: "\n")
        let remaining = candidates.count - min(8, candidates.count)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clean \(media.name) before ejecting?"
        alert.informativeText = "FIND950 found \(candidates.count) configured metadata item(s) to remove:\n\n"
            + preview
            + (remaining > 0 ? "\n• …and \(remaining) more" : "")
            + "\n\nFIND950 will verify that every configured item is gone before ejecting. Exceptions and custom cleanup names can be changed in Settings."
        alert.addButton(withTitle: "Clean & Eject")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .cleanAndEject
        default: return .cancel
        }
    }

    private func nativeEject(_ media: FindMediaVolume) async throws {
        try await Task.detached(priority: .userInitiated) {
            try NSWorkspace.shared.unmountAndEjectDevice(at: media.mountURL)
        }.value
    }

    var librarySearchResults: [LibrarySearchResult] {
        guard !searchText.isEmpty else { return [] }
        return visibleLibraryImages.flatMap { image in
            image.volumes.flatMap { volume in
                volume.entries.compactMap { entry in
                    entry.name.localizedCaseInsensitiveContains(searchText)
                        && itemHasSelectedTag(image: image, volume: volume, entry: entry)
                        ? LibrarySearchResult(image: image, volume: volume, entry: entry)
                        : nil
                }
            }
        }
    }

    var collectedEntries: [LibrarySearchResult] {
        if let cachedCollectedEntries { return cachedCollectedEntries }
        let entries = collectedEntryIDs.compactMap { entryLookup[$0] }.sorted {
            let imageOrder = $0.image.name.localizedStandardCompare($1.image.name)
            if imageOrder != .orderedSame { return imageOrder == .orderedAscending }
            if $0.volume.path != $1.volume.path {
                return $0.volume.path.localizedStandardCompare($1.volume.path) == .orderedAscending
            }
            return $0.entry.index < $1.entry.index
        }
        cachedCollectedEntries = entries
        return entries
    }

    var collectionManifest: FindCollectionManifest {
        if let cachedCollectionManifest { return cachedCollectionManifest }
        let explicit = collectedEntries
        let exportEntries = explicit.sorted { left, right in
            let imageOrder = left.image.name.localizedStandardCompare(right.image.name)
            if imageOrder != .orderedSame { return imageOrder == .orderedAscending }
            if left.volume.path != right.volume.path {
                return left.volume.path.localizedStandardCompare(right.volume.path) == .orderedAscending
            }
            return left.entry.index < right.entry.index
        }
        let collisions = Dictionary(grouping: exportEntries) {
            P9ReferenceParser.nativeFilenameKey($0.entry.name)
        }.filter { $0.value.count > 1 }.keys.sorted()

        let manifest = FindCollectionManifest(
            explicitEntries: explicit,
            exportEntries: exportEntries,
            filenameCollisions: collisions
        )
        cachedCollectionManifest = manifest
        return manifest
    }

    func isCollected(
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    ) -> Bool {
        collectedEntryIDs.contains(itemKey(image: image, volume: volume, entry: entry))
    }

    func toggleCollected(
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    ) {
        let key = itemKey(image: image, volume: volume, entry: entry)
        setCollected(
            entryIDs: [key],
            collected: !collectedEntryIDs.contains(key),
            actionName: collectedEntryIDs.contains(key)
                ? "Remove from Collection" : "Add to Collection"
        )
    }

    func setCollected(
        entryIDs: Set<String>,
        collected: Bool,
        actionName: String = "Change Collection"
    ) {
        let eligible = Set(entryIDs.filter { id in
            guard let context = entryContext(for: id) else { return false }
            return context.entry.kind == .sample || context.entry.kind == .program
        })
        guard !eligible.isEmpty else { return }
        let previous = collectedEntryIDs
        if collected {
            collectedEntryIDs.formUnion(eligible)
        } else {
            collectedEntryIDs.subtract(eligible)
        }
        guard previous != collectedEntryIDs else { return }
        persistCollection()
        undoManager?.registerSuiteUndo(
            withTarget: self,
            actionName: actionName
        ) { target in
            target.restoreCollection(previous, actionName: actionName)
        }
    }

    func clearCollection() {
        let previous = collectedEntryIDs
        guard !previous.isEmpty else { return }
        collectedEntryIDs.removeAll()
        persistCollection()
        undoManager?.registerSuiteUndo(
            withTarget: self,
            actionName: "Clear Collection"
        ) { target in
            target.restoreCollection(previous, actionName: "Clear Collection")
        }
    }

    func visibleEntries(_ entries: [S950LibraryEntry], image: S950ImageCatalog, volume: S950VolumeCatalog) -> [S950LibraryEntry] {
        entries.filter { entry in
            (searchText.isEmpty || entry.name.localizedCaseInsensitiveContains(searchText))
                && itemHasSelectedTag(image: image, volume: volume, entry: entry)
        }
    }

    func isFolderVisible(_ url: URL) -> Bool {
        !hiddenFolderPaths.contains(url.standardizedFileURL.path)
    }

    func toggleFolderVisibility(_ url: URL) {
        let path = url.standardizedFileURL.path
        if hiddenFolderPaths.contains(path) {
            hiddenFolderPaths.remove(path)
        } else {
            hiddenFolderPaths.insert(path)
        }
        UserDefaults.standard.set(Array(hiddenFolderPaths).sorted(), forKey: hiddenFoldersDefaultsKey)
        if !images.contains(where: { $0.id == selectedImageID }) {
            selectedImageID = images.first?.id
        }
    }

    func itemKey(image: S950ImageCatalog, volume: S950VolumeCatalog, entry: S950LibraryEntry) -> String {
        "\(image.imageURL.standardizedFileURL.path)|\(volume.path)|\(entry.id)"
    }

    func tagsFor(image: S950ImageCatalog) -> [LibraryTag] {
        tagsFor(target: .image(image.imageURL))
    }

    func tagsFor(image: S950ImageCatalog, volume: S950VolumeCatalog, entry: S950LibraryEntry) -> [LibraryTag] {
        tagsFor(target: tagTarget(image: image, volume: volume, entry: entry))
    }

    func toggleTag(_ tag: LibraryTag, image: S950ImageCatalog) {
        toggleTag(tag, target: .image(image.imageURL))
    }

    func toggleTag(_ tag: LibraryTag, image: S950ImageCatalog, volume: S950VolumeCatalog, entry: S950LibraryEntry) {
        toggleTag(tag, target: tagTarget(image: image, volume: volume, entry: entry))
    }

    func isTagAssigned(_ tag: LibraryTag, image: S950ImageCatalog) -> Bool {
        isTagAssigned(tag, target: .image(image.imageURL))
    }

    func isTagAssigned(
        _ tag: LibraryTag,
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    ) -> Bool {
        isTagAssigned(
            tag,
            target: tagTarget(image: image, volume: volume, entry: entry)
        )
    }

    func addTag() {
        mutateTags(actionName: "Add Tag") { document in
            let usedNames = Set(document.tags.map { $0.name.lowercased() })
            var number = document.tags.count + 1
            while usedNames.contains("tag \(number)") { number += 1 }
            document.tags.append(
                LibraryTag(name: "Tag \(number)", colorHex: "#6E7581")
            )
        }
    }

    func updateTag(_ tag: LibraryTag, name: String? = nil, colorHex: String? = nil) {
        mutateTags(actionName: "Edit Tag") { document in
            guard let index = document.tags.firstIndex(where: { $0.id == tag.id }) else {
                return
            }
            if let name { document.tags[index].name = name }
            if let colorHex { document.tags[index].colorHex = colorHex }
        }
    }

    func deleteTag(_ tag: LibraryTag) {
        mutateTags(actionName: "Delete Tag") { $0.removeTag(tag.id) }
        if selectedTagFilterID == tag.id { selectedTagFilterID = nil }
    }

    func reloadSharedTags() {
        let resolvedDirectory = SharedTagLibrary.resolvedDirectoryURL(
            preferredDirectoryURL: libraryDataDirectoryURL
        )
        if resolvedDirectory != tagLibrary.directoryURL {
            tagLibrary = SharedTagLibrary(directoryURL: resolvedDirectory)
            tagLibraryDirectoryURL = resolvedDirectory
        }
        do {
            applyTagDocument(try tagLibrary.bootstrap(
                legacyMetadataURL: LibraryMetadataPersistence
                    .legacyMetadataFileURL(in: libraryDataDirectoryURL)
            ))
        } catch {
            errorMessage = "Couldn’t reload shared library tags: \(error.localizedDescription)"
        }
    }

    func showProgramsUsing(image: S950ImageCatalog, volume: S950VolumeCatalog, sample: S950LibraryEntry) {
        let sampleName = normalizedSampleName(sample.name)
        let programs = volume.programs.filter { program in
            program.sampleReferences.contains { P9ReferenceParser.normalized($0) == sampleName }
        }
        relatedPrograms = RelatedProgramsContext(
            image: image,
            volume: volume,
            sample: sample,
            programs: programs
        )
    }

    var selectedEntry: (
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    )? { selectedEntryContext() }

    func requestSearchFocus() {
        searchFocusRequest &+= 1
    }

    func requestMainPaneFocus() {
        mainPaneFocusRequest &+= 1
    }

    func selectEntry(
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    ) {
        selectedEntryID = itemKey(image: image, volume: volume, entry: entry)
    }

    func selectEntry(withID id: String) {
        guard let context = entryContext(for: id) else { return }
        selectEntry(image: context.image, volume: context.volume, entry: context.entry)
    }

    func handleSpaceForSelectedEntry() -> Bool {
        guard let context = selectedEntryContext(),
              context.image.id == selectedImageID else { return false }
        guard context.entry.kind == .sample else { return true }
        toggleAudition(image: context.image, volume: context.volume, sample: context.entry)
        return true
    }

    func showInFinder(_ url: URL) {
        let target = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: target.path) else {
            errorMessage = "Couldn’t show \(target.lastPathComponent) in Finder because it is no longer at \(target.path)."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func addFolders() {
        diagnostics.record(.info, category: "ui", message: "Add IMG folders dialogue shown")
        let panel = NSOpenPanel()
        panel.title = "Add folders containing S900/S950 IMG backups"
        panel.prompt = "Add to Library"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else {
            diagnostics.record(.info, category: "ui", message: "Add IMG folders dialogue cancelled")
            return
        }
        diagnostics.record(
            .info,
            category: "library",
            message: "IMG folders added",
            fields: [
                "count": String(panel.urls.count),
                "folders": panel.urls.map(\.path).joined(separator: " | ")
            ]
        )
        var known = Set(folderURLs.map { $0.standardizedFileURL })
        folderURLs.append(contentsOf: panel.urls.map(\.standardizedFileURL).filter { known.insert($0).inserted })
        folderURLs.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        persistFolders()
        refreshMediaVolumes()
        scanFolders()
    }

    func removeFolder(_ url: URL) {
        diagnostics.record(
            .info,
            category: "library",
            message: "IMG folder removed",
            fields: ["folder": url.path]
        )
        let index = folderURLs.firstIndex {
            $0.standardizedFileURL == url.standardizedFileURL
        }
        let wasHidden = hiddenFolderPaths.contains(url.standardizedFileURL.path)
        folderURLs.removeAll { $0.standardizedFileURL == url.standardizedFileURL }
        hiddenFolderPaths.remove(url.standardizedFileURL.path)
        UserDefaults.standard.set(Array(hiddenFolderPaths).sorted(), forKey: hiddenFoldersDefaultsKey)
        persistFolders()
        refreshMediaVolumes()
        scanFolders()
        if let index {
            undoManager?.registerSuiteUndo(
                withTarget: self,
                actionName: "Remove IMG Folder"
            ) { target in
                target.restoreFolder(url, at: index, hidden: wasHidden)
            }
        }
    }

    func chooseLibraryDataDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Cached Library Data Location"
        panel.message = "Choose the folder where FIND950 should keep its cached library data. Synced folders such as Dropbox are supported."
        panel.prompt = "Use This Folder"
        panel.directoryURL = libraryDataDirectoryURL
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setLibraryDataDirectory(url.standardizedFileURL)
    }

    func resetLibraryDataDirectory() {
        setLibraryDataDirectory(LibraryMetadataPersistence.defaultDirectoryURL, useDefaultPreference: true)
    }

    func chooseTagLibraryDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Shared Tag Index Location"
        panel.message = "Choose the folder where FIND950 and EDIT950 should keep their shared tag index. Synced folders can be used, but avoid editing tags on multiple Macs at the same time."
        panel.prompt = "Use This Folder"
        panel.directoryURL = tagLibraryDirectoryURL
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setTagLibraryDirectory(url)
    }

    func resetTagLibraryDirectory() {
        setTagLibraryDirectory(SharedTagLibrary.defaultDirectoryURL)
    }

    func exportTagIndex() {
        let panel = NSSavePanel()
        panel.title = "Export Shared Tag Index"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "950TOOLS-tags-v2.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tagLibrary.export(to: url)
            notice = BrowserNotice(
                title: "Shared Tag Index Exported",
                message: "Saved a portable copy at \(url.path)."
            )
        } catch {
            errorMessage = "Couldn’t export shared library tags: \(error.localizedDescription)"
        }
    }

    func revealTagIndex() {
        NSWorkspace.shared.activateFileViewerSelecting([tagLibraryFileURL])
    }

    func scanFolders() {
        audition.stop()
        auditioningID = nil
        if isScanning {
            scanPending = true
            diagnostics.record(
                .debug,
                category: "scan",
                message: "Additional scan queued while scan is active"
            )
            return
        }
        guard !folderURLs.isEmpty else {
            collection = S950LibraryCollection(folderURLs: [], images: [], failures: [])
            selectedImageID = nil
            diagnostics.record(
                .info,
                category: "scan",
                message: "Library cleared because no IMG folders are configured"
            )
            return
        }
        let helper: URL
        do {
            helper = try BundledAkaiUtil.locate()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let requestedFolders = folderURLs
        let volumeLeases: [VolumeUseLease]
        do {
            volumeLeases = try beginVolumeUse(
                for: requestedFolders,
                detail: "Scanning IMG folders"
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let cachedIndex = indexCache
        let indexURL = LibraryMetadataPersistence.indexFileURL(
            in: libraryDataDirectoryURL
        )
        isScanning = true
        errorMessage = nil
        diagnostics.record(
            .info,
            category: "scan",
            message: "Library scan started",
            fields: [
                "folders": String(requestedFolders.count),
                "recursive": "true"
            ]
        )
        Task {
            defer { releaseVolumeUse(volumeLeases) }
            let update = await Task.detached(priority: .utility) {
                await S950LibraryScanner(helperURL: helper).scanIncrementally(
                    folderURLs: requestedFolders,
                    recursive: true,
                    cached: cachedIndex
                )
            }.value
            if requestedFolders == folderURLs {
                indexCache = update.index
                collection = update.collection
                refreshMediaVolumes()
                if !images.contains(where: {
                    $0.id == selectedImageID
                }) {
                    selectedImageID = images.first?.id
                }
                do {
                    try update.index.write(to: indexURL)
                } catch {
                    errorMessage = "Couldn’t save the IMG index cache: \(error.localizedDescription)"
                }
                let actionableFailures = update.collection.failures.filter {
                    mediaVolume(containing: $0.imageURL)?.isAvailable != false
                }
                if !actionableFailures.isEmpty {
                    errorMessage = "Some images could not be read:\n"
                        + actionableFailures.prefix(5)
                        .map { "\($0.imageURL.lastPathComponent): \($0.message)" }
                        .joined(separator: "\n")
                }
                diagnostics.record(
                    actionableFailures.isEmpty ? .info : .warning,
                    category: "scan",
                    message: "Library scan completed",
                    fields: [
                        "images": String(update.collection.images.count),
                        "programs": String(
                            update.collection.images.reduce(0) { $0 + $1.programCount }
                        ),
                        "samples": String(
                            update.collection.images.reduce(0) { $0 + $1.sampleCount }
                        ),
                        "failures": String(actionableFailures.count)
                    ]
                )
            } else {
                scanPending = true
                diagnostics.record(
                    .debug,
                    category: "scan",
                    message: "Scan result superseded by a folder change"
                )
            }
            isScanning = false
            if scanPending {
                scanPending = false
                scanFolders()
            }
        }
    }

    func rescanImage(_ image: S950ImageCatalog) {
        diagnostics.record(
            .info,
            category: "scan",
            message: "Forced IMG rescan requested",
            fields: ["image": image.imageURL.path]
        )
        indexCache = S950LibraryIndexDocument(
            records: indexCache.records.filter {
                $0.catalog.imageURL.standardizedFileURL != image.imageURL.standardizedFileURL
            }
        )
        selectedImageID = image.id
        scanFolders()
    }

    func exportSampleAsWAV(
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        sample: S950LibraryEntry
    ) {
        guard requireAvailable(image, action: "export \(sample.name)") else { return }
        let panel = NSSavePanel()
        panel.title = "Export Sample as WAV"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "\((sample.name as NSString).deletingPathExtension).wav"
        panel.allowedContentTypes = [.wav]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else {
            diagnostics.record(
                .info,
                category: "export",
                message: "Sample WAV export cancelled",
                fields: ["sample": sample.name]
            )
            return
        }
        diagnostics.record(
            .info,
            category: "export",
            message: "Sample WAV export started",
            fields: [
                "sample": sample.name,
                "image": image.imageURL.path,
                "volume": volume.path,
                "destination": destination.path
            ]
        )
        let helperURL: URL
        do {
            helperURL = try BundledAkaiUtil.locate()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let volumeLeases: [VolumeUseLease]
        do {
            volumeLeases = try beginVolumeUse(
                for: [image.imageURL],
                detail: "Exporting sample: \(sample.name)"
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isWorking = true
        Task {
            defer { releaseVolumeUse(volumeLeases) }
            let workspace = FileManager.default.temporaryDirectory
                .appendingPathComponent("find950-wav-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: workspace) }
            do {
                let exported = try await S950LibraryScanner(helperURL: helperURL)
                    .exportSampleForAudition(
                        imageURL: image.imageURL,
                        volumePath: volume.path,
                        sample: sample,
                        destinationFolder: workspace
                    )
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: exported, to: destination)
                notice = BrowserNotice(
                    title: "Sample Exported",
                    message: "Verified \(sample.name) at \(destination.path)."
                )
            } catch {
                errorMessage = "Couldn’t export \(sample.name): \(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    func toggleAudition(image: S950ImageCatalog, volume: S950VolumeCatalog, sample: S950LibraryEntry) {
        let id = auditionID(image: image, volume: volume, sample: sample)
        if auditioningID == id {
            audition.stop()
            auditioningID = nil
            diagnostics.record(
                .info,
                category: "audition",
                message: "Sample audition stopped",
                fields: ["sample": sample.name]
            )
            return
        }
        guard requireAvailable(image, action: "audition \(sample.name)") else { return }
        audition.stop()
        auditioningID = id
        errorMessage = nil
        diagnostics.record(
            .info,
            category: "audition",
            message: "Sample audition requested",
            fields: [
                "sample": sample.name,
                "image": image.imageURL.path,
                "volume": volume.path
            ]
        )
        let volumeLeases: [VolumeUseLease]
        do {
            volumeLeases = try beginVolumeUse(
                for: [image.imageURL],
                detail: "Preparing audition: \(sample.name)"
            )
        } catch {
            auditioningID = nil
            errorMessage = error.localizedDescription
            return
        }
        Task {
            defer { releaseVolumeUse(volumeLeases) }
            let workspace = URL(fileURLWithPath: "/tmp", isDirectory: true)
                .appendingPathComponent("s950-audition-\(UUID().uuidString)", isDirectory: true)
            do {
                let helperURL = try BundledAkaiUtil.locate()
                let wavURL = try await S950LibraryScanner(helperURL: helperURL).exportSampleForAudition(
                    imageURL: image.imageURL,
                    volumePath: volume.path,
                    sample: sample,
                    destinationFolder: workspace
                )
                guard auditioningID == id else {
                    try? FileManager.default.removeItem(at: workspace)
                    return
                }
                try audition.play(wavURL: wavURL, workspaceURL: workspace)
                diagnostics.record(
                    .info,
                    category: "audition",
                    message: "Sample audition playing",
                    fields: ["sample": sample.name]
                )
            } catch {
                try? FileManager.default.removeItem(at: workspace)
                if auditioningID == id { auditioningID = nil }
                errorMessage = "Couldn’t audition \(sample.name): \(error.localizedDescription)"
            }
        }
    }

    func isAuditioning(image: S950ImageCatalog, volume: S950VolumeCatalog, sample: S950LibraryEntry) -> Bool {
        auditioningID == auditionID(image: image, volume: volume, sample: sample)
    }

    func openInEDIT950(_ image: S950ImageCatalog) {
        guard requireAvailable(image, action: "open \(image.name)") else { return }
        let requestID = UUID().uuidString
        diagnostics.record(
            .info,
            category: "handoff",
            message: "Opening IMG in EDIT950",
            fields: [
                "requestID": requestID,
                "image": image.imageURL.path
            ]
        )
        do {
            let volumeLeases = try beginVolumeUse(
                for: [image.imageURL],
                detail: "Handing IMG to EDIT950: \(image.name)"
            )
            let application = try locateEDIT950Application()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            Task {
                defer { releaseVolumeUse(volumeLeases) }
                do {
                    try await NSWorkspace.shared.open(
                        [image.imageURL],
                        withApplicationAt: application,
                        configuration: configuration
                    )
                    diagnostics.record(
                        .info,
                        category: "handoff",
                        message: "IMG handed to EDIT950",
                        fields: [
                            "requestID": requestID,
                            "image": image.imageURL.path
                        ]
                    )
                } catch {
                    errorMessage = "Couldn’t open \(image.name) in EDIT950: \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openProgramInPLAY950(
        image: S950ImageCatalog,
        program: S950LibraryEntry
    ) {
        guard requireAvailable(image, action: "open \(program.name) in PLAY950") else {
            return
        }
        let requestID = UUID().uuidString
        diagnostics.record(
            .info,
            category: "handoff",
            message: "Program sent to PLAY950",
            fields: [
                "requestID": requestID,
                "image": image.imageURL.path,
                "program": program.name
            ]
        )
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.e45recordings.PLAY950.LoadContent"),
            object: nil,
            userInfo: [
                "path": image.imageURL.path,
                "program": (program.name as NSString).deletingPathExtension,
                "requestID": requestID
            ],
            deliverImmediately: true
        )
        // Compatibility post for installed builds carrying the previous product name.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.e45recordings.TRUE950.LoadContent"),
            object: nil,
            userInfo: [
                "path": image.imageURL.path,
                "program": (program.name as NSString).deletingPathExtension,
                "requestID": requestID
            ],
            deliverImmediately: true
        )
        notice = BrowserNotice(
            title: "Sent to PLAY950",
            message: "Asked the open PLAY950 editor in your DAW to load \(program.name) from \(image.name). Keep the PLAY950 plug-in window open to receive it."
        )
    }

    func exportProgramInEDIT950(
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        program: S950LibraryEntry,
        exportMode: String = "image"
    ) {
        guard requireAvailable(image, action: "export \(program.name)") else { return }
        let volumeLeases: [VolumeUseLease]
        do {
            volumeLeases = try beginVolumeUse(
                for: [image.imageURL],
                detail: "Exporting program: \(program.name)"
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        diagnostics.record(
            .info,
            category: "handoff",
            message: "Program export through EDIT950 requested",
            fields: [
                "image": image.imageURL.path,
                "volume": volume.path,
                "program": program.name,
                "mode": exportMode
            ]
        )
        isWorking = true
        errorMessage = nil
        Task {
            defer { releaseVolumeUse(volumeLeases) }
            do {
                let application = try locateEDIT950Application()
                let transfer = S950ProgramTransfer()
                let handoff = try transfer.prepareHandoff(
                    sourceImage: image.imageURL,
                    sourceVolumePath: volume.path,
                    program: program,
                    sourceEntries: volume.entries,
                    exportMode: exportMode
                )
                diagnostics.record(
                    .info,
                    category: "handoff",
                    message: "Program handoff prepared",
                    fields: [
                        "requestID": handoff.request.requestID.uuidString,
                        "program": program.name,
                        "mode": exportMode
                    ]
                )
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                do {
                    try await NSWorkspace.shared.open(
                        [handoff.requestURL],
                        withApplicationAt: application,
                        configuration: configuration
                    )
                } catch {
                    handoff.cleanup()
                    throw error
                }
                let response = try await transfer.waitForTerminalResponse(
                    to: handoff,
                    onAccepted: { response in
                        await MainActor.run {
                            self.notice = BrowserNotice(
                                title: exportMode == "abletonDrumRack"
                                    ? "Ableton Export Accepted by EDIT950"
                                    : "Export Accepted by EDIT950",
                                message: "Switch to EDIT950 and complete its export dialogue. "
                                    + (response.summary
                                        ?? "EDIT950 selected \(program.name) and is waiting for destination choices.")
                            )
                        }
                    }
                )
                diagnostics.record(
                    response.status == .completed ? .info : .warning,
                    category: "handoff",
                    message: "EDIT950 returned a terminal program-export response",
                    fields: [
                        "requestID": response.requestID.uuidString,
                        "status": response.status.rawValue,
                        "errorCode": response.errorCode ?? "none",
                        "summary": response.summary ?? "none"
                    ]
                )
                switch response.status {
                case .completed:
                    if exportMode == "abletonDrumRack" {
                        notice = BrowserNotice(
                            title: "Ableton Drum Rack Exported",
                            message: response.summary ?? response.details?["packagePath"] ?? "EDIT950 completed the Ableton Drum Rack export."
                        )
                        break
                    }
                    guard let result = response.result else {
                        throw S950LibraryError.invalidHandoff(
                            "EDIT950 reported completion without protocol-v1 result evidence."
                        )
                    }
                    let backup = result.backupPath.map { " Backup: \($0)." } ?? ""
                    notice = BrowserNotice(
                        title: "Program Exported and Verified",
                        message: "\(result.program.filename) and \(result.dependencies.count) sample dependency file(s) were verified in \(result.resultingImage.path). SHA-256: \(result.resultingImage.sha256).\(backup)"
                    )
                    scanFolders()
                case .failed:
                    errorMessage = "EDIT950 export failed [\(response.errorCode ?? "unknown")]: \(response.summary ?? "No detail returned.")"
                case .rejected:
                    errorMessage = "EDIT950 rejected the export [\(response.errorCode ?? "unknown")]: \(response.summary ?? "No detail returned.")"
                case .accepted:
                    throw S950LibraryError.invalidHandoff(
                        "The acknowledgement wait ended without a terminal response."
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    func exportCollectionInEDIT950() {
        let manifest = collectionManifest
        diagnostics.record(
            .info,
            category: "handoff",
            message: "Collection export through EDIT950 requested",
            fields: [
                "files": String(manifest.fileCount),
                "bytes": String(manifest.totalBytes),
                "blockers": String(manifest.exportBlockers.count)
            ]
        )
        guard manifest.exportBlockers.isEmpty else {
            errorMessage = manifest.exportBlockers.joined(separator: "\n\n")
            return
        }
        let offlineImages = Set(manifest.exportEntries.compactMap {
            isImageAvailable($0.image) ? nil : $0.image.name
        }).sorted()
        guard offlineImages.isEmpty else {
            errorMessage = "Reconnect this media before exporting the collection: "
                + offlineImages.joined(separator: ", ")
            return
        }
        let selections = manifest.exportEntries.map {
            S950CollectionTransfer.Selection(
                sourceImage: $0.image.imageURL,
                volumePath: $0.volume.path,
                entry: $0.entry
            )
        }
        let volumeLeases: [VolumeUseLease]
        do {
            volumeLeases = try beginVolumeUse(
                for: selections.map(\.sourceImage),
                detail: "Exporting FIND950 collection"
            )
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        isWorking = true
        collectionExportStatus = "PREPARING…"
        errorMessage = nil
        Task {
            defer { releaseVolumeUse(volumeLeases) }
            do {
                let application = try locateEDIT950Application()
                let handoff = try await Task.detached(priority: .userInitiated) {
                    try S950CollectionTransfer().prepareHandoff(selections: selections)
                }.value
                diagnostics.record(
                    .info,
                    category: "handoff",
                    message: "Collection handoff prepared",
                    fields: [
                        "requestID": handoff.request.requestID.uuidString,
                        "files": String(manifest.fileCount)
                    ]
                )
                collectionExportStatus = "OPENING EDIT950…"
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                do {
                    try await NSWorkspace.shared.open(
                        [handoff.requestURL],
                        withApplicationAt: application,
                        configuration: configuration
                    )
                } catch {
                    handoff.cleanup()
                    throw error
                }
                collectionExportStatus = "WAITING FOR EDIT950…"
                let response = try await S950CollectionTransfer().waitForTerminalResponse(
                    to: handoff,
                    onAccepted: { response in
                        await MainActor.run {
                            self.collectionExportStatus = "CHOOSE DESTINATION IN EDIT950"
                            self.notice = BrowserNotice(
                                title: "Collection Accepted by EDIT950",
                                message: response.summary
                                    ?? "Switch to EDIT950 to choose the fresh IMG destination."
                            )
                        }
                    }
                )
                diagnostics.record(
                    response.status == .completed ? .info : .warning,
                    category: "handoff",
                    message: "EDIT950 returned a terminal collection-export response",
                    fields: [
                        "requestID": response.requestID.uuidString,
                        "status": response.status.rawValue,
                        "errorCode": response.errorCode ?? "none",
                        "summary": response.summary ?? "none"
                    ]
                )
                switch response.status {
                case .completed:
                    let path = response.details?["resultingImage"] ?? "the chosen IMG"
                    let count = response.details?["importedFileCount"] ?? String(manifest.fileCount)
                    let hash = response.details?["destinationSHA256"].map { " SHA-256: \($0)." } ?? ""
                    notice = BrowserNotice(
                        title: "Collection Exported and Verified",
                        message: "EDIT950 verified \(count) native file(s) in \(path).\(hash)"
                    )
                    scanFolders()
                case .failed:
                    errorMessage = "EDIT950 collection export failed [\(response.errorCode ?? "unknown")]: \(response.summary ?? "No detail returned.")"
                case .rejected:
                    let summary = response.summary ?? "No detail returned."
                    if response.errorCode == "malformedRequest",
                       summary.localizedCaseInsensitiveContains(
                           "unexpected protocol-v1 field: sources"
                       ) {
                        errorMessage = "The installed EDIT950 is older than FIND950's multi-disk collection export. Update EDIT950, then try again. No IMG was changed."
                    } else {
                        errorMessage = "EDIT950 rejected the collection [\(response.errorCode ?? "unknown")]: \(summary)"
                    }
                case .accepted:
                    throw S950LibraryError.invalidHandoff(
                        "The acknowledgement wait ended without a terminal response."
                    )
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            collectionExportStatus = nil
            isWorking = false
        }
    }

    private func locateEDIT950Application() throws -> URL {
        if let edit950ApplicationURL,
           FileManager.default.fileExists(atPath: edit950ApplicationURL.path) { return edit950ApplicationURL }
        let candidates = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.e45recordings.EDIT950"),
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.local.AKAIImageManager"),
            URL(fileURLWithPath: "/Applications/EDIT950.app"),
            URL(fileURLWithPath: "/Applications/AKAI Image Manager.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/EDIT950.app"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/AKAI Image Manager.app")
        ].compactMap { $0 }
        if let application = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            edit950ApplicationURL = application
            return application
        }

        let panel = NSOpenPanel()
        panel.title = "Locate EDIT950"
        panel.prompt = "Open With This App"
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let application = panel.url else {
            throw BrowserError.edit950NotFound
        }
        edit950ApplicationURL = application
        return application
    }

    private func auditionID(image: S950ImageCatalog, volume: S950VolumeCatalog, sample: S950LibraryEntry) -> String {
        "\(image.imageURL.path)|\(volume.path)|\(sample.id)"
    }

    private func requireAvailable(
        _ image: S950ImageCatalog,
        action: String
    ) -> Bool {
        guard isImageAvailable(image) else {
            let mediaName = mediaVolume(for: image)?.name
            errorMessage = "Reconnect \(mediaName.map { "\($0) " } ?? "")to \(action). The cached catalogue remains available for browsing and search."
            return false
        }
        return true
    }

    private func itemHasSelectedTag(
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    ) -> Bool {
        guard let selectedTagFilterID else { return true }
        if tagAssignments[SharedTagTarget.image(image.imageURL).storageKey]?
            .contains(selectedTagFilterID) == true {
            return true
        }
        return tagAssignments[
            tagTarget(image: image, volume: volume, entry: entry).storageKey
        ]?.contains(selectedTagFilterID) == true
    }

    private func imageHasSelectedTag(_ image: S950ImageCatalog) -> Bool {
        guard let selectedTagFilterID else { return true }
        if tagAssignments[SharedTagTarget.image(image.imageURL).storageKey]?
            .contains(selectedTagFilterID) == true {
            return true
        }
        return image.volumes.contains { volume in
            volume.entries.contains { entry in
                tagAssignments[
                    tagTarget(image: image, volume: volume, entry: entry).storageKey
                ]?.contains(selectedTagFilterID) == true
            }
        }
    }

    private func normalizedSampleName(_ name: String) -> String {
        P9ReferenceParser.normalized((name as NSString).deletingPathExtension)
    }

    private func tagTarget(
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    ) -> SharedTagTarget {
        let kind: SharedTagTargetKind
        switch entry.kind {
        case .program: kind = .program
        case .sample: kind = .sample
        default: kind = .other
        }
        return .entry(
            imageURL: image.imageURL,
            volumePath: volume.path,
            kind: kind,
            filename: entry.name
        )
    }

    private func tagsFor(target: SharedTagTarget) -> [LibraryTag] {
        let assigned = tagAssignments[target.storageKey] ?? []
        return tags.filter { assigned.contains($0.id) }
    }

    private func isTagAssigned(
        _ tag: LibraryTag,
        target: SharedTagTarget
    ) -> Bool {
        tagAssignments[target.storageKey]?.contains(tag.id) == true
    }

    private func toggleTag(_ tag: LibraryTag, target: SharedTagTarget) {
        mutateTags(actionName: "Change Tags") { $0.toggle(tag.id, for: target) }
    }

    private func mutateTags(
        actionName: String,
        _ mutation: (inout SharedTagDocument) throws -> Void
    ) {
        do {
            let previous = try tagLibrary.load()
            let updated = try tagLibrary.update(mutation)
            applyTagDocument(updated)
            guard previous != updated else { return }
            undoManager?.registerSuiteUndo(
                withTarget: self,
                actionName: actionName
            ) { target in
                target.restoreTagDocument(previous, actionName: actionName)
            }
        } catch {
            errorMessage = "Couldn’t update shared library tags: \(error.localizedDescription)"
        }
    }

    private func applyTagDocument(_ document: SharedTagDocument) {
        tags = document.tags
        tagAssignments = document.assignments
        if let selectedTagFilterID,
           !tags.contains(where: { $0.id == selectedTagFilterID }) {
            self.selectedTagFilterID = nil
        }
    }

    private func restoreTagDocument(
        _ document: SharedTagDocument,
        actionName: String
    ) {
        do {
            let inverse = try tagLibrary.load()
            let restored = try tagLibrary.update { $0 = document }
            applyTagDocument(restored)
            undoManager?.registerSuiteUndo(
                withTarget: self,
                actionName: actionName
            ) { target in
                target.restoreTagDocument(inverse, actionName: actionName)
            }
        } catch {
            errorMessage = "Couldn’t undo the shared tag change: \(error.localizedDescription)"
        }
    }

    private func restoreCollection(_ collection: Set<String>, actionName: String) {
        let inverse = collectedEntryIDs
        collectedEntryIDs = collection
        persistCollection()
        undoManager?.registerSuiteUndo(
            withTarget: self,
            actionName: actionName
        ) { target in
            target.restoreCollection(inverse, actionName: actionName)
        }
    }

    private func restoreFolder(_ url: URL, at index: Int, hidden: Bool) {
        let insertion = min(max(index, 0), folderURLs.count)
        folderURLs.insert(url.standardizedFileURL, at: insertion)
        if hidden { hiddenFolderPaths.insert(url.standardizedFileURL.path) }
        persistFolders()
        UserDefaults.standard.set(Array(hiddenFolderPaths).sorted(), forKey: hiddenFoldersDefaultsKey)
        undoManager?.registerSuiteUndo(
            withTarget: self,
            actionName: "Remove IMG Folder"
        ) { target in
            target.removeFolder(url)
        }
        scanFolders()
    }

    private func setTagLibraryDirectory(_ requestedURL: URL) {
        let destinationURL = requestedURL.standardizedFileURL
        guard destinationURL != tagLibrary.directoryURL else { return }
        let previousURL = tagLibrary.directoryURL
        do {
            let destination = SharedTagLibrary(directoryURL: destinationURL)
            if FileManager.default.fileExists(atPath: destination.fileURL.path) {
                let currentDocument = try tagLibrary.load()
                let destinationDocument = try destination.load()
                if currentDocument != destinationDocument {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "This folder already contains a tag index."
                    alert.informativeText = "Use Existing switches both apps to that index. Replace with Current copies the current shared tags over it. The current index remains at its old location as a backup."
                    alert.addButton(withTitle: "Use Existing")
                    alert.addButton(withTitle: "Replace with Current")
                    alert.addButton(withTitle: "Cancel")
                    switch alert.runModal() {
                    case .alertFirstButtonReturn:
                        SharedTagLibrary.activateDirectoryURL(destinationURL)
                        tagLibrary = destination
                    case .alertSecondButtonReturn:
                        tagLibrary = try tagLibrary.relocate(to: destinationURL)
                    default:
                        return
                    }
                } else {
                    SharedTagLibrary.activateDirectoryURL(destinationURL)
                    tagLibrary = destination
                }
            } else {
                tagLibrary = try tagLibrary.relocate(to: destinationURL)
            }
            tagLibraryDirectoryURL = destinationURL
            applyTagDocument(try tagLibrary.load())
            notice = BrowserNotice(
                title: "Shared Tag Index Location Updated",
                message: "FIND950 and EDIT950 now use \(tagLibrary.fileURL.path). A backup copy remains at \(previousURL.appendingPathComponent(SharedTagLibrary.filename).path)."
            )
        } catch {
            errorMessage = "Couldn’t use that shared tag index location: \(error.localizedDescription)"
        }
    }

    private func persistFolders() {
        UserDefaults.standard.set(folderURLs.map(\.path), forKey: defaultsKey)
    }

    private func persistCollection() {
        UserDefaults.standard.set(Array(collectedEntryIDs).sorted(), forKey: collectionDefaultsKey)
    }

    private func persistMediaCleanupPolicy() {
        guard let data = try? JSONEncoder().encode(mediaCleanupPolicy) else { return }
        UserDefaults.standard.set(data, forKey: mediaCleanupDefaultsKey)
    }

    private func invalidateCollectionCache() {
        cachedCollectedEntries = nil
        cachedCollectionManifest = nil
    }

    private func rebuildEntryLookup() {
        var lookup: [String: LibrarySearchResult] = [:]
        for image in collection?.images ?? [] {
            for volume in image.volumes {
                for entry in volume.entries {
                    let result = LibrarySearchResult(
                        image: image,
                        volume: volume,
                        entry: entry
                    )
                    lookup[itemKey(image: image, volume: volume, entry: entry)] = result
                }
            }
        }
        entryLookup = lookup
    }

    private func selectedEntryContext() -> (
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    )? {
        guard let selectedEntryID else { return nil }
        return entryContext(for: selectedEntryID)
    }

    private func entryContext(for id: String) -> (
        image: S950ImageCatalog,
        volume: S950VolumeCatalog,
        entry: S950LibraryEntry
    )? {
        guard let result = entryLookup[id] else { return nil }
        return (result.image, result.volume, result.entry)
    }

    private func setLibraryDataDirectory(_ url: URL, useDefaultPreference: Bool = false) {
        guard url != libraryDataDirectoryURL else { return }
        do {
            try indexCache.write(
                to: LibraryMetadataPersistence.indexFileURL(in: url)
            )
            if useDefaultPreference {
                UserDefaults.standard.removeObject(forKey: LibraryMetadataPersistence.locationDefaultsKey)
            } else {
                UserDefaults.standard.set(url.path, forKey: LibraryMetadataPersistence.locationDefaultsKey)
            }
            libraryDataDirectoryURL = url
            scanFolders()
        } catch {
            errorMessage = "Couldn’t use that library data location: \(error.localizedDescription)"
        }
    }

    private static func diagnosticFileStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

private enum BrowserError: LocalizedError {
    case edit950NotFound
    var errorDescription: String? {
        "EDIT950 was not found. Install it in Applications or choose the app manually."
    }
}

@MainActor
private final class SafeSampleAuditionController: NSObject, AVAudioPlayerDelegate {
    var onPlaybackEnded: (() -> Void)?
    private var player: AVAudioPlayer?
    private var workspaceURL: URL?

    func play(wavURL: URL, workspaceURL: URL) throws {
        stop()
        let player = try AVAudioPlayer(contentsOf: wavURL)
        guard player.duration > 0, player.prepareToPlay(), player.play() else {
            throw BrowserErrorAudio.emptyTemporaryWAV
        }
        self.workspaceURL = workspaceURL
        self.player = player
        player.delegate = self
    }

    func stop() {
        player?.stop()
        player = nil
        cleanup()
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            self?.finishPlayback()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.finishPlayback()
        }
    }

    private func finishPlayback() {
        self.player = nil
        cleanup()
        onPlaybackEnded?()
    }

    private func cleanup() {
        if let workspaceURL { try? FileManager.default.removeItem(at: workspaceURL) }
        workspaceURL = nil
    }
}

private enum BrowserErrorAudio: LocalizedError {
    case emptyTemporaryWAV
    var errorDescription: String? { "The temporary WAV contains no playable audio." }
}

private struct LibrarySettingsView: View {
    @ObservedObject var model: Find950Model
    @EnvironmentObject private var preferences: SuitePreferences
    @State private var customCleanupName = ""
    @State private var cleanupException = ""

    var body: some View {
        Form {
            Section("APPEARANCE") {
                Picker("THEME", selection: $preferences.appearance) {
                    ForEach(SuiteAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Picker("DISPLAY ZOOM", selection: $preferences.zoom) {
                    ForEach(SuiteZoomLevel.allCases) { zoom in
                        Text(zoom.title).tag(zoom)
                    }
                }
                .pickerStyle(.segmented)
                Picker("TABLE DENSITY", selection: $preferences.density) {
                    ForEach(SuiteDensity.allCases) { density in Text(density.title).tag(density) }
                }
                .pickerStyle(.segmented)
                Toggle("SHOW FOLDERS SIDEBAR", isOn: $preferences.sidebarVisible)
                Toggle("SHOW INSPECTOR", isOn: $preferences.inspectorVisible)
                Toggle("SHOW COLLECTION PANE", isOn: $preferences.collectionVisible)
            }
            Section("INCLUDED COMPONENTS") {
                LabeledContent("AKAI Util", value: "4.6.7 · Universal")
                Text("AKAI Util is included with FIND950 and is used read-only to inspect IMG files and prepare temporary audition audio. No separate download, path selection or Terminal setup is required. Safe Eject is handled by native FIND950 code.")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
            }
            Section("DIAGNOSTICS") {
                Toggle(
                    "OPEN DIAGNOSTIC LOG WHEN AN ERROR OCCURS",
                    isOn: $model.autoOpenDiagnosticLogOnError
                )
                Text("FIND950 continuously keeps a size-limited, user-readable activity timeline. It records actions, dialogue state, scans, exports, handoffs and errors—not IMG, program, sample or audio contents. Home and temporary paths are shortened.")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                HStack {
                    Button("Show Live Log") { model.isLogVisible = true }
                    Button("Save Copy…") { model.saveDiagnosticLog() }
                    Button("Reveal in Finder") { model.revealDiagnosticLog() }
                }
            }
            Section("CLEAN EJECT") {
                Text("FIND950 applies the enabled metadata rules, including AppleDouble ._* sidecars, and verifies that every match is gone before ejecting. Full Disk Access is required to remove protected .Spotlight-V100 data.")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
                Button("Open Full Disk Access Settings") {
                    model.openFullDiskAccessSettings()
                }
                Text("Default metadata rules")
                    .font(SuiteFont.medium(11))
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 7
                ) {
                    ForEach(RemovableMediaCleanupPolicy.defaultNames, id: \.self) { name in
                        Toggle(name, isOn: Binding(
                            get: { model.mediaCleanupPolicy.isDefaultEnabled(name) },
                            set: { model.setDefaultCleanupName(name, enabled: $0) }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }

                LabeledContent("Custom exact names") {
                    VStack(alignment: .trailing, spacing: 7) {
                        ForEach(model.mediaCleanupPolicy.customNames, id: \.self) { name in
                            HStack {
                                Text(name).textSelection(.enabled)
                                Button {
                                    model.removeCustomCleanupName(name)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .help("REMOVE CUSTOM CLEANUP NAME")
                            }
                        }
                        HStack {
                            TextField("e.g. .MySamplerCache", text: $customCleanupName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCustomCleanupName)
                            Button("Add") { addCustomCleanupName() }
                                .disabled(customCleanupName.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty)
                        }
                    }
                    .frame(maxWidth: 390, alignment: .trailing)
                }

                LabeledContent("Exceptions") {
                    VStack(alignment: .trailing, spacing: 7) {
                        ForEach(model.mediaCleanupPolicy.exceptions, id: \.self) { exception in
                            HStack {
                                Text(exception).textSelection(.enabled)
                                Button {
                                    model.removeCleanupException(exception)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .help("REMOVE CLEANUP EXCEPTION")
                            }
                        }
                        HStack {
                            TextField("name or relative/path", text: $cleanupException)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCleanupException)
                            Button("Add") { addCleanupException() }
                                .disabled(cleanupException.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty)
                        }
                    }
                    .frame(maxWidth: 390, alignment: .trailing)
                }
                HStack {
                    Text("Exact names match at any depth. An exception can be a leaf name everywhere or one path relative to the media root. FIND950 always previews matches before deleting.")
                        .font(SuiteFont.regular(10))
                        .foregroundStyle(Color.suiteUnit)
                    Spacer()
                    Button("Reset Defaults") { model.resetMediaCleanupPolicy() }
                }
            }
            Section("Library Cache") {
                LabeledContent("Cached library data") {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(model.libraryDataDirectoryURL.path)
                            .foregroundStyle(Color.suiteUnit)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        HStack {
                            Button("Reset to Default") { model.resetLibraryDataDirectory() }
                                .disabled(model.libraryDataDirectoryURL == LibraryMetadataPersistence.defaultDirectoryURL)
                            Button("Choose…") { model.chooseLibraryDataDirectory() }
                        }
                    }
                    .frame(maxWidth: 390, alignment: .trailing)
                }
                Text("The generated search index is stored here. Your IMG files are never moved, and the shared tag index has its own location below.")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
            }
            Section("Shared Tag Index") {
                LabeledContent("Current file") {
                    Text(model.tagLibraryFileURL.path)
                        .foregroundStyle(Color.suiteUnit)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: 390, alignment: .trailing)
                }
                HStack {
                    Button("Show in Finder") { model.revealTagIndex() }
                    Spacer()
                    Button("Reset to Default") { model.resetTagLibraryDirectory() }
                        .disabled(
                            model.tagLibraryDirectoryURL
                                == SharedTagLibrary.defaultDirectoryURL
                        )
                    Button("Choose Location…") { model.chooseTagLibraryDirectory() }
                }
                HStack {
                    Spacer()
                    Button("Export Copy…") { model.exportTagIndex() }
                }
                Text("This versioned JSON file contains shared tag names, colours and IMG/P9/S9 assignments. FIND950 and EDIT950 use the same selected location. Relocating it leaves the previous copy as a backup. Synced folders can be used, but avoid editing tags on multiple Macs simultaneously.")
                    .font(SuiteFont.regular(10))
                    .foregroundStyle(Color.suiteUnit)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.suiteBackground)
        .frame(width: 720, height: 680)
        .navigationTitle("Settings")
    }

    private func addCustomCleanupName() {
        if model.addCustomCleanupName(customCleanupName) { customCleanupName = "" }
    }

    private func addCleanupException() {
        if model.addCleanupException(cleanupException) { cleanupException = "" }
    }
}
