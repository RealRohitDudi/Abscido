import Foundation
import Security

/// On macOS 26, `tccd` refuses to show the Speech Recognition permission dialog for bare
/// SwiftPM executables — it crashes the process with `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__`
/// even when the entitlement and `NSSpeechRecognitionUsageDescription` are embedded.
/// The only reliable fix is to launch through a proper `.app` bundle registered with Launch Services.
///
/// This bootstrap:
/// 1. Creates `Abscido.app` next to the bare binary (copies it, re-signs, writes Info.plist).
/// 2. Registers the bundle with `lsregister`.
/// 3. Launches it via `/usr/bin/open -nW` (the standard macOS app launch path).
/// 4. The current (bare) process stays alive as a proxy until the `.app` exits.
///
/// Call `ensureEntitlement()` as the **first** thing in `App.init()`.
enum SpeechEntitlementBootstrap {

    private static let entitlementKey = "com.apple.security.personal-information.speech-recognition"

    /// Live check against the kernel's code-signature cache for this process.
    static var hasEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, entitlementKey as CFString, nil) != nil
    }

    static func ensureEntitlement() {
        let exe = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? ""

        // Already inside the .app bundle with the entitlement — nothing to do.
        if hasEntitlement && isInsideAppBundle(exe) {
            log("Running from .app bundle with entitlement — ready.")
            return
        }

        // If we're already inside the bundle but missing the entitlement (shouldn't happen),
        // bail out rather than looping.
        if isInsideAppBundle(exe) {
            log("Inside .app bundle but entitlement missing — cannot fix, continuing.")
            return
        }

        log("Bare executable detected: \(exe)")

        guard FileManager.default.isWritableFile(atPath: exe) else {
            log("Binary not writable — skipping.")
            return
        }

        let sourceDir  = URL(fileURLWithPath: exe).deletingLastPathComponent()
        let appBundle  = sourceDir.appendingPathComponent("Abscido.app")
        let contentsDir = appBundle.appendingPathComponent("Contents")
        let macOSDir    = contentsDir.appendingPathComponent("MacOS")
        let bundleBin   = macOSDir.appendingPathComponent("Abscido")
        let infoPlist   = contentsDir.appendingPathComponent("Info.plist")

        do {
            try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
            try Self.infoPlistXML.write(to: infoPlist, atomically: true, encoding: .utf8)
            log("Wrote Info.plist")

            if FileManager.default.fileExists(atPath: bundleBin.path) {
                try FileManager.default.removeItem(at: bundleBin)
            }
            try FileManager.default.copyItem(atPath: exe, toPath: bundleBin.path)
            log("Copied binary into bundle.")

            try resignBinary(at: bundleBin.path)
            log("Re-signed bundle binary.")
        } catch {
            log("Bundle creation failed: \(error.localizedDescription)")
            return
        }

        // Register with Launch Services so tccd can look up the bundle.
        let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework"
            + "/Versions/A/Frameworks/LaunchServices.framework"
            + "/Versions/A/Support/lsregister"
        if FileManager.default.fileExists(atPath: lsregisterPath) {
            let lsr = Process()
            lsr.executableURL = URL(fileURLWithPath: lsregisterPath)
            lsr.arguments = ["-f", appBundle.path]
            lsr.standardOutput = FileHandle.nullDevice
            lsr.standardError  = FileHandle.nullDevice
            try? lsr.run()
            lsr.waitUntilExit()
            log("Registered with Launch Services.")
        }

        // Launch through `open` — the standard macOS launch path. This ensures
        // Launch Services, tccd, and the window server all know about the .app.
        // -n: new instance  -W: wait for app to quit (so swift run stays alive)
        log("Launching Abscido.app via /usr/bin/open ...")
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", "-W", appBundle.path]
        open.standardOutput = FileHandle.standardOutput
        open.standardError  = FileHandle.standardError

        guard (try? open.run()) != nil else {
            log("`open` failed to launch — falling back to direct execution.")
            return
        }

        // Block until the .app quits so `swift run` stays alive in the terminal.
        open.waitUntilExit()
        log("App exited with status \(open.terminationStatus).")
        exit(open.terminationStatus)
    }

    // MARK: - Helpers

    private static func isInsideAppBundle(_ path: String) -> Bool {
        path.contains(".app/Contents/MacOS/")
    }

    private static func resignBinary(at path: String) throws {
        let entitlements =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
            + "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
            + "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
            + "<plist version=\"1.0\">\n<dict>\n"
            + "  <key>com.apple.security.get-task-allow</key>\n  <true/>\n"
            + "  <key>\(entitlementKey)</key>\n  <true/>\n"
            + "</dict>\n</plist>\n"

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("abscido-ent-\(ProcessInfo.processInfo.processIdentifier).plist")
        try entitlements.write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let cs = Process()
        cs.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        cs.arguments = ["--force", "--sign", "-", "--timestamp=none", "--entitlements", tmp.path, path]
        cs.standardOutput = FileHandle.nullDevice
        cs.standardError  = FileHandle.nullDevice
        try cs.run()
        cs.waitUntilExit()
        guard cs.terminationStatus == 0 else {
            throw NSError(domain: "SpeechBootstrap", code: Int(cs.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "codesign exited \(cs.terminationStatus)"])
        }
    }

    // MARK: - Info.plist

    private static let infoPlistXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" \
        "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleDevelopmentRegion</key>
            <string>en</string>
            <key>CFBundleExecutable</key>
            <string>Abscido</string>
            <key>CFBundleIdentifier</key>
            <string>com.abscido.mac</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>CFBundleName</key>
            <string>Abscido</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>NSSpeechRecognitionUsageDescription</key>
            <string>Abscido transcribes the audio track of clips you import so you can edit by deleting words.</string>
            <key>NSMicrophoneUsageDescription</key>
            <string>Microphone access is optional; transcription uses imported files.</string>
        </dict>
        </plist>
        """

    private static func log(_ message: String) {
        var msg = "[SpeechBootstrap] \(message)\n"
        msg.withUTF8 { buffer in
            _ = fwrite(buffer.baseAddress, 1, buffer.count, stderr)
            fflush(stderr)
        }
    }
}
