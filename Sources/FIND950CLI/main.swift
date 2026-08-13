import Foundation
import S950Library

@main
struct S950LibraryCommand {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.contains("--help") || arguments.isEmpty {
                printUsage()
                return
            }

            var folderPath: String?
            var helperPath: String?
            var recursive = false
            var json = false
            var index = 0
            while index < arguments.count {
                switch arguments[index] {
                case "--akaiutil":
                    index += 1
                    guard index < arguments.count else { throw CLIError.missingValue("--akaiutil") }
                    helperPath = arguments[index]
                case "--recursive": recursive = true
                case "--json": json = true
                default:
                    guard folderPath == nil else { throw CLIError.unexpected(arguments[index]) }
                    folderPath = arguments[index]
                }
                index += 1
            }
            guard let folderPath else { throw CLIError.missingFolder }

            let helper = try AkaiUtilLocator.locate(explicitPath: helperPath)
            let scan = try await S950LibraryScanner(helperURL: helper).scan(
                folderURL: URL(fileURLWithPath: folderPath, isDirectory: true),
                recursive: recursive
            )
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                print(String(decoding: try encoder.encode(scan), as: UTF8.self))
            } else {
                printScan(scan)
            }
            if !scan.failures.isEmpty { exit(EXIT_FAILURE) }
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func printScan(_ scan: S950LibraryScan) {
        if scan.images.isEmpty { print("No .IMG files found in \(scan.folderURL.path)") }
        for image in scan.images {
            print("\n\(image.name) — \(image.programCount) program(s), \(image.sampleCount) sample(s)")
            for volume in image.volumes {
                print("  \(volume.name)")
                for program in volume.programs { print("    Program  \(program.name)") }
                for sample in volume.samples { print("    Sample   \(sample.name)") }
            }
        }
        for failure in scan.failures {
            FileHandle.standardError.write(Data("\nCould not read \(failure.imageURL.lastPathComponent): \(failure.message)\n".utf8))
        }
    }

    private static func printUsage() {
        print("""
        Browse the programs and samples in a folder of S900/S950 IMG backups.

        Usage:
          find950-cli <folder> [--recursive] [--json] [--akaiutil <path>]

        AKAI Util is discovered from --akaiutil, AKAIUTIL_PATH, EDIT950
        in /Applications, or PATH. Images are always opened read-only.
        """)
    }
}

private enum CLIError: LocalizedError {
    case missingFolder
    case missingValue(String)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .missingFolder: return "Provide a folder containing .IMG files."
        case .missingValue(let option): return "\(option) requires a path."
        case .unexpected(let value): return "Unexpected argument: \(value)"
        }
    }
}
