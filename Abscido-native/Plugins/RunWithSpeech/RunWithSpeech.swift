import Foundation
import PackagePlugin

@main
struct RunWithSpeech: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let root = context.package.directory
        let entitlements = root.appending("Abscido", "LocalSigning.entitlements")
        guard FileManager.default.fileExists(atPath: entitlements.string) else {
            throw RunError("Missing entitlements at \(entitlements.string)")
        }

        try run(
            "/usr/bin/swift",
            ["build"] + arguments,
            cwd: root,
            capture: false
        )

        let binDir = try run(
            "/usr/bin/swift",
            ["build"] + arguments + ["--show-bin-path"],
            cwd: root,
            capture: true
        ).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard !binDir.isEmpty else {
            throw RunError("swift build --show-bin-path returned empty output")
        }

        let binaryPath = (binDir as NSString).appendingPathComponent("Abscido")
        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw RunError("Built binary not found at \(binaryPath)")
        }

        try run(
            "/usr/bin/codesign",
            [
                "--force",
                "--sign",
                "-",
                "--timestamp=none",
                "--entitlements",
                entitlements.string,
                binaryPath,
            ],
            cwd: root,
            capture: false
        )

        try run(binaryPath, [], cwd: root, capture: false)
    }

    @discardableResult
    private func run(_ launch: String, _ args: [String], cwd: PackagePlugin.Path, capture: Bool) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd.string)

        let pipe = Pipe()
        if capture {
            p.standardOutput = pipe
            p.standardError = pipe
        } else {
            p.standardOutput = FileHandle.standardOutput
            p.standardError = FileHandle.standardError
        }

        try p.run()
        p.waitUntilExit()

        if capture {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            guard p.terminationStatus == 0 else {
                throw RunError("Command failed (status \(p.terminationStatus)): \(launch) \(args.joined(separator: " "))\n\(text)")
            }
            return text
        }

        guard p.terminationStatus == 0 else {
            throw RunError("Command failed (status \(p.terminationStatus)): \(launch) \(args.joined(separator: " "))")
        }
        return ""
    }
}

private struct RunError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) {
        self.errorDescription = message
    }
}
