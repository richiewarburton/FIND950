@preconcurrency import Foundation

actor AkaiUtilSession {
    static let allowedReadOnlyVerbs: Set<String> = [
        "df", "dinfo", "pwd", "dir", "ls", "dirrec", "lsrec",
        "infoi", "infoall", "help", "lcd", "cd", "cdi", "geti",
        "sample2wavi"
    ]
    private var process: Process?
    private var input: FileHandle?
    private var stream: AsyncStream<Data>?
    private var iterator: AsyncStream<Data>.Iterator?
    private var continuation: AsyncStream<Data>.Continuation?
    private var buffer = ""

    func open(imageURL: URL, helperURL: URL) async throws {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw S950LibraryError.helperNotExecutable(helperURL.path)
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = helperURL
        var arguments: [String] = ["-r"]
        if Self.isFloppySized(imageURL) { arguments.append("-f") }
        arguments.append(imageURL.path)
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let pair = AsyncStream<Data>.makeStream()
        stream = pair.stream
        iterator = pair.stream.makeAsyncIterator()
        continuation = pair.continuation
        outputPipe.fileHandleForReading.readabilityHandler = { [continuation = pair.continuation] handle in
            let data = handle.availableData
            if data.isEmpty {
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        process.terminationHandler = { [continuation = pair.continuation] _ in continuation.finish() }

        try process.run()
        self.process = process
        input = inputPipe.fileHandleForWriting
        _ = try await readUntilPrompt()
        guard process.isRunning else { throw S950LibraryError.helperExited("") }
    }

    func send(_ command: String) async throws -> String {
        guard !command.isEmpty,
              !command.contains("\n"),
              !command.contains("\r"),
              let input,
              process?.isRunning == true
        else { throw S950LibraryError.helperExited("The image session is not available.") }
        let verb = command.split(whereSeparator: \.isWhitespace).first
            .map { String($0).lowercased() } ?? ""
        guard Self.allowedReadOnlyVerbs.contains(verb) else {
            throw S950LibraryError.readOnlyCommandRequired(verb)
        }
        try input.write(contentsOf: Data((command + "\n").utf8))
        return try await readUntilPrompt()
    }

    func close() async {
        if let process, process.isRunning {
            try? input?.write(contentsOf: Data("q\n".utf8))
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    process.waitUntilExit()
                    continuation.resume()
                }
            }
        }
        input?.closeFile()
        input = nil
        process?.terminationHandler = nil
        process = nil
        continuation?.finish()
        continuation = nil
        iterator = nil
        stream = nil
        buffer = ""
    }

    private func readUntilPrompt() async throws -> String {
        while true {
            if let range = AkaiPrompt.terminalRange(in: buffer) {
                let result = String(buffer[..<range.upperBound])
                buffer = String(buffer[range.upperBound...])
                return result
            }
            guard var current = iterator else { throw S950LibraryError.promptNotFound(buffer) }
            let data = await current.next()
            iterator = current
            guard let data else { throw S950LibraryError.promptNotFound(buffer) }
            buffer.append(String(decoding: data, as: UTF8.self))
        }
    }

    private static func isFloppySized(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.uint64Value
        return size == 800 * 1024 || size == 1600 * 1024
    }
}
