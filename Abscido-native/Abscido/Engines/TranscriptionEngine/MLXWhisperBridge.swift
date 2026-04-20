import Foundation

/// Bridges to the bundled Python runtime to execute MLX-Whisper transcription.
/// Launches and manages the Python subprocess, streams stdout/stderr.
final class MLXWhisperBridge: Sendable {

    /// Runs the transcription Python script and returns the JSON output.
    func runTranscription(
        wavPath: String,
        language: String,
        modelName: String = "mlx-community/whisper-large-v3-mlx",
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
            process.environment = ProcessInfo.processInfo.environment.merging(
                ["ABSCIDO_CACHE_DIR": cacheDir],
                uniquingKeysWith: { _, new in new }
            )

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
                    // Parse progress from stderr JSON lines
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

                if proc.terminationStatus == 0 {
                    if let output = String(data: stdoutData, encoding: .utf8) {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: AbscidoError.transcriptionFailed(
                            clipId: 0, pythonError: "Could not decode stdout"
                        ))
                    }
                } else {
                    let errorMessage = String(data: stderrData, encoding: .utf8) ?? "Unknown Python error"
                    continuation.resume(throwing: AbscidoError.transcriptionFailed(
                        clipId: 0, pythonError: errorMessage
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

    // MARK: - Path Resolution

    private func findPythonBinary() -> String {
        // Check bundled Python first
        if let bundledPath = Bundle.main.path(
            forResource: "python3.12",
            ofType: nil,
            inDirectory: "python"
        ) {
            return bundledPath
        }

        // Fallback to system Python (for development)
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

    private func findTranscribeScript() -> String {
        if let bundledPath = Bundle.main.path(
            forResource: "transcribe",
            ofType: "py",
            inDirectory: "scripts"
        ) {
            return bundledPath
        }
        // Development fallback
        return Bundle.main.bundlePath + "/Contents/Resources/scripts/transcribe.py"
    }

    private func modelCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("Abscido/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Progress Message

private struct ProgressMessage: Decodable {
    let progress: Double
}
