import Foundation

/// Bridges to the bundled Python runtime to execute MLX-Whisper transcription.
/// Launches and manages the Python subprocess, streams stdout/stderr.
final class MLXWhisperBridge: Sendable {

    /// Default MLX-Whisper model. `whisper-tiny` (~75 MB) downloads quickly and runs fast.
    /// Switch to `mlx-community/whisper-small-mlx` or `mlx-community/whisper-large-v3-mlx`
    /// for higher accuracy at the cost of download size and inference time.
    static let defaultModelName = "mlx-community/whisper-tiny"

    /// Runs the transcription Python script and returns the JSON output.
    func runTranscription(
        wavPath: String,
        language: String,
        modelName: String = MLXWhisperBridge.defaultModelName,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> String {
        let pythonPath = findPythonBinary()
        let scriptPath = findTranscribeScript()

        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw AbscidoError.pythonRuntimeMissing
        }
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            throw AbscidoError.fileNotFound(path: scriptPath)
        }

        let cacheDir = modelCacheDirectory().path

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = [scriptPath, wavPath, language, modelName]
            /// GUI apps inherit a minimal PATH (no `/opt/homebrew/bin`), but **mlx-whisper** shells
            /// out to **`ffmpeg`** — see `mlx_whisper/audio.py`. Prepend common install locations.
            process.environment = Self.subprocessEnvironment(extra: ["ABSCIDO_CACHE_DIR": cacheDir])

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            var stdoutData = Data()
            var stderrData = Data()

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stdoutData.append(data)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stderrData.append(data)
                    if let line = String(data: data, encoding: .utf8) {
                        for part in line.components(separatedBy: "\n") {
                            if let jsonData = part.data(using: .utf8),
                               let progress = try? JSONDecoder().decode(
                                   ProgressMessage.self, from: jsonData
                               ) {
                                onProgress(progress.progress)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { proc in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil

                let stdoutText = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrText = String(data: stderrData, encoding: .utf8) ?? ""

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdoutText)
                } else {
                    // transcribe.py reports failures with `{"error":"..."}` on stdout (exit 1) and
                    // streams `{"progress":…}` JSON lines on stderr — using raw stderr hides the cause.
                    let message = Self.pythonFailureUserMessage(
                        stdout: stdoutText,
                        stderr: stderrText,
                        status: proc.terminationStatus
                    )
                    continuation.resume(throwing: AbscidoError.transcriptionFailed(
                        clipId: 0, pythonError: message
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AbscidoError.transcriptionFailed(
                    clipId: 0, pythonError: error.localizedDescription
                ))
            }
        }
    }

    // MARK: - Subprocess environment

    /// FFmpeg binary paths commonly used on Apple Silicon Intel Homebrew/MacPorts installs.
    private static let ffmpegCandidatePaths: [String] = [
        "/opt/homebrew/bin/ffmpeg",
        "/opt/homebrew/opt/ffmpeg/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/local/opt/ffmpeg/bin/ffmpeg",
        "/opt/local/bin/ffmpeg",
    ]

    /// Directories to prepend to `PATH` (includes keg prefixes that are not symlinked into `bin`).
    private static let toolPathPrefixes: [String] = [
        "/opt/homebrew/bin",
        "/opt/homebrew/opt/ffmpeg/bin",
        "/usr/local/bin",
        "/usr/local/opt/ffmpeg/bin",
        "/opt/local/bin",
    ]

    /// Merges caller keys first, then wires **`PATH`** / **`ABSCIDO_FFMPEG`** so Python can find Homebrew ffmpeg.
    private static func subprocessEnvironment(extra: [String: String]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        for (k, v) in extra {
            env[k] = v
        }

        // Optional override: `export ABSCIDO_FFMPEG=/path/to/ffmpeg` before launch.
        if let ff = env["ABSCIDO_FFMPEG"], ff.isEmpty == false,
           FileManager.default.isExecutableFile(atPath: ff) == false {
            env.removeValue(forKey: "ABSCIDO_FFMPEG")
        }

        if env["ABSCIDO_FFMPEG"]?.isEmpty != false {
            if let found = ffmpegCandidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
                env["ABSCIDO_FFMPEG"] = found
            }
        }

        let existingPATH = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var pathParts = toolPathPrefixes
        if let ff = env["ABSCIDO_FFMPEG"], ff.isEmpty == false {
            let dir = (ff as NSString).deletingLastPathComponent
            if dir.isEmpty == false { pathParts.insert(dir, at: 0) }
        }
        if let exe = ffmpegCandidatePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let dir = (exe as NSString).deletingLastPathComponent
            if dir.isEmpty == false { pathParts.insert(dir, at: 0) }
        }

        env["PATH"] = pathParts.uniquedPreservingOrder().joined(separator: ":") + ":" + existingPATH
        return env
    }

    // MARK: - Path Resolution

    private func findPythonBinary() -> String {
        if let bundledPath = Bundle.main.path(
            forResource: "python3.12",
            ofType: nil,
            inDirectory: "python"
        ) {
            return bundledPath
        }

        let possiblePaths = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "/usr/bin/python3"
    }

    /// SPM copies resources into a sibling `.bundle` (e.g. `Abscido_Abscido.bundle/scripts/`), not `.app/Contents/Resources`.
    private func findTranscribeScript() -> String {
        let fm = FileManager.default

        if let override = ProcessInfo.processInfo.environment["ABSCIDO_TRANSCRIBE_SCRIPT"],
           fm.fileExists(atPath: override) {
            return override
        }

        if let p = Bundle.main.path(forResource: "transcribe", ofType: "py", inDirectory: "scripts"),
           fm.fileExists(atPath: p) {
            return p
        }

        if let url = Bundle.main.url(forResource: "transcribe", withExtension: "py", subdirectory: "scripts"),
           fm.fileExists(atPath: url.path) {
            return url.path
        }

        // Directory that contains the `Abscido` executable (`swift build` → `.build/.../debug/`).
        let bundlePathURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let execDir = bundlePathURL.lastPathComponent == "MacOS"
            ? bundlePathURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            : bundlePathURL.deletingLastPathComponent()

        if let items = try? fm.contentsOfDirectory(at: execDir, includingPropertiesForKeys: nil) {
            for bundleURL in items where bundleURL.pathExtension == "bundle" {
                let script = bundleURL.appendingPathComponent("scripts/transcribe.py").path
                if fm.fileExists(atPath: script) {
                    return script
                }
            }
        }

        // Walk up toward repo root (`…/Abscido-native/Abscido/Resources/scripts/transcribe.py`).
        var walk = execDir.standardizedFileURL
        for _ in 0 ..< 14 {
            let candidate = walk.appendingPathComponent("Abscido/Resources/scripts/transcribe.py").path
            if fm.fileExists(atPath: candidate) {
                return candidate
            }
            let parent = walk.deletingLastPathComponent().standardizedFileURL
            if parent == walk { break }
            walk = parent
        }

        return execDir.appendingPathComponent("Abscido_Abscido.bundle/scripts/transcribe.py").path
    }

    private func modelCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("Abscido/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// `write_error` in `transcribe.py` prints a single JSON object to stdout; progress lives on stderr.
    private static func pythonFailureUserMessage(stdout: String, stderr: String, status: Int32) -> String {
        let trimmedOut = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmedOut.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PythonStdoutError.self, from: data) {
            return payload.error
        }

        let stderrWithoutProgress = nonProgressDiagnosticLines(stderr)
        if stderrWithoutProgress.isEmpty == false {
            return stderrWithoutProgress
        }

        let code = procExitDescription(status)
        if trimmedOut.isEmpty {
            return "Python transcription exited with \(code). No error details were returned."
        }
        return "Python transcription exited with \(code). Output:\n\(trimmedOut)"
    }

    private static func nonProgressDiagnosticLines(_ stderr: String) -> String {
        stderr
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard t.isEmpty == false else { return false }
                guard let data = t.data(using: .utf8) else { return true }
                if (try? JSONDecoder().decode(ProgressMessage.self, from: data)) != nil {
                    return false
                }
                return true
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func procExitDescription(_ status: Int32) -> String {
        if status >= 0 {
            return "code \(status)"
        }
        // macOS: exit status encodes signal for killed processes
        return "status \(status)"
    }
}

private extension [String] {
    func uniquedPreservingOrder() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Progress Message

private struct ProgressMessage: Decodable {
    let progress: Double
}

private struct PythonStdoutError: Decodable {
    let error: String
}
