import CryptoKit
import Foundation

// Native SwiftPM accessors only search the app root and an absolute build path.
// macOS signing requires these resources inside Contents/Resources. A compiler
// overlay adjusts generated accessors for app builds without editing a dependency.
guard CommandLine.arguments.count == 3 ||
        (CommandLine.arguments.count == 4 && CommandLine.arguments[3] == "--verify-generated") else {
    fatalError("Usage: prepare-resource-overlay.swift <bin-path> <output-directory> [--verify-generated]")
}

let products = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let output = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
let modules = ["KeyboardShortcuts", "SwiftTerm"]

func generatedAccessor(for module: String) -> URL {
    products.appendingPathComponent("\(module).build/DerivedSources/resource_bundle_accessor.swift")
}

if CommandLine.arguments.count == 4 {
    // Fail packaging if a SwiftPM update moves/renames an accessor and our VFS
    // mapping no longer covers the source the compiler actually receives.
    for module in modules {
        let source = try String(contentsOf: generatedAccessor(for: module), encoding: .utf8)
        guard source.contains("\(module)_\(module).bundle"), source.contains("module: Bundle") else {
            fatalError("Unexpected generated resource accessor for \(module)")
        }
    }
    exit(EXIT_SUCCESS)
}

let sources = modules.map { module in
    """
    import Foundation

    extension Foundation.Bundle {
        static nonisolated let module: Bundle = {
            let name = "\(module)_\(module).bundle"
            for directory in [Bundle.main.resourceURL, Bundle.main.bundleURL] {
                if let url = directory?.appendingPathComponent(name),
                   let bundle = Bundle(url: url) {
                    return bundle
                }
            }
            Swift.fatalError("Missing packaged resource bundle: \\(name)")
        }()
    }
    """
}

// A changed implementation or product path changes compiler arguments too, so
// SwiftPM cannot reuse objects compiled with an older overlay.
let generator = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[0]))
let fingerprint = SHA256.hash(data: generator + Data(([products.path] + sources).joined().utf8))
    .map { String(format: "%02x", $0) }.joined()
let directory = output.appendingPathComponent(fingerprint)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func writeIfChanged(_ data: Data, to url: URL) throws {
    if (try? Data(contentsOf: url)) != data {
        try data.write(to: url, options: .atomic)
    }
}

var roots: [[String: String]] = []
for (module, source) in zip(modules, sources) {
    let replacement = directory.appendingPathComponent("\(module).swift")
    try writeIfChanged(Data(source.utf8), to: replacement)
    roots.append([
        "type": "file",
        "name": generatedAccessor(for: module).path,
        "external-contents": replacement.path,
    ])
}
let overlay = directory.appendingPathComponent("overlay.json")
try writeIfChanged(
    JSONSerialization.data(withJSONObject: ["version": 0, "roots": roots], options: [.sortedKeys]),
    to: overlay
)
print(overlay.path)
