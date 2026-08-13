import Foundation

enum AkaiPrompt {
    private static let pattern = #"(?m)(^|\n)(/[^\r\n]*) > $"#

    static func terminalRange(in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.matches(in: text, range: range).last,
              match.range.location + match.range.length == (text as NSString).length
        else { return nil }
        return Range(match.range, in: text)
    }

    static func path(in text: String) -> String? {
        guard let range = terminalRange(in: text) else { return nil }
        let value = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasSuffix(" >") ? String(value.dropLast(2)) : value
    }
}

enum AkaiOutputParser {
    static func volumes(from output: String) -> [String] {
        var paths: [String] = []
        for rawLine in lines(output) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix(" >") { line = String(line.dropLast(2)) }
            guard line.hasPrefix("/disk") else { continue }
            let parts = line.split(separator: "/")
            guard parts.count >= 3 else { continue }
            let path = "/" + parts.prefix(3).joined(separator: "/")
            if !paths.contains(path) { paths.append(path) }
        }
        return paths
    }

    static func directory(from output: String) -> [S950LibraryEntry] {
        let pattern = #"^\s*(\d+)\s+(.+?)\s+(\d+)\s+(0x[0-9a-fA-F]+)(?:\s+(\S+))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return lines(output).compactMap { line in
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  let index = capture(match, 1, in: line).flatMap(Int.init),
                  let name = capture(match, 2, in: line)?.trimmingCharacters(in: .whitespaces),
                  let byteSize = capture(match, 3, in: line).flatMap(Int64.init)
            else { return nil }
            return S950LibraryEntry(index: index, name: name, byteSize: byteSize, kind: kind(for: name))
        }
    }

    private static func kind(for filename: String) -> S950EntryKind {
        S950EntryKind.classify(filename: filename)
    }

    private static func lines(_ output: String) -> [String] {
        output.replacingOccurrences(of: "\r", with: "\n").components(separatedBy: .newlines)
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges,
              match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: text)
        else { return nil }
        return String(text[range])
    }
}
