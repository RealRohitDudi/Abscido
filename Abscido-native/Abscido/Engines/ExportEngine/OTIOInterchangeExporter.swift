import Foundation
import OpenTimelineIO

/// Editorial interchange derived from Abscido’s bridge timeline (the same layout used for playback).
///
/// Swift OpenTimelineIO does not ship Python adapter plugins (`fcp_xml`, etc.). FCP 7 XML and FCPXML 1.10
/// are emitted by walking track children in order: **gaps advance the record timeline but emit no clip row**,
/// matching common adapter semantics from [otio-fcp-adapter](https://github.com/OpenTimelineIO/otio-fcp-adapter).
enum OTIOInterchangeExporter: Sendable {

    // MARK: - Public API

    /// Serializes the timeline with the native OpenTimelineIO JSON encoder (``.otio``).
    ///
    /// Abscido attaches private clip metadata (`abscido_*`) and may set non-default ``globalStartTime``.
    /// Some OTIO C++ builds return ``OTIOError.Status.notImplemented`` when serializing certain
    /// combinations; we export a **cloned** timeline with private metadata removed and
    /// ``globalStartTime`` cleared so the file matches stock OTIO interchange expectations.
    static func writeOTIOJSON(timeline: Timeline, to url: URL) throws {
        let cloned = try timeline.clone()
        guard let copy = cloned as? Timeline else {
            throw AbscidoError.exportFailed(reason: "Could not duplicate timeline for .otio export.")
        }
        copy.globalStartTime = nil
        scrubAbscidoPrivateMetadata(from: copy)
        try copy.toJSON(url: url)
    }

    /// Removes Abscido-only metadata keys so native OTIO JSON serialization succeeds.
    private static func scrubAbscidoPrivateMetadata(from timeline: Timeline) {
        guard let stack = timeline.tracks else { return }
        for composable in stack.children {
            guard let track = composable as? Track else { continue }
            for i in 0..<track.children.count {
                guard let clip = track.children[i] as? Clip else { continue }
                clip.metadata["abscido_mediaFileId"] = nil
                clip.metadata["abscido_linkGroupId"] = nil
            }
        }
    }

    /// FCP 7 XML (xmeml) — DaVinci Resolve, Premiere Pro, legacy FCP.
    static func buildFCP7XML(
        bridgeTimeline: OTIOTimeline,
        mediaFiles: [MediaFile],
        projectName: String
    ) throws -> String {
        guard !bridgeTimeline.tracks.isEmpty else {
            throw AbscidoError.xmlExportFailed(format: "FCP7", reason: "Timeline has no tracks.")
        }

        let seqRate = editingRate(for: bridgeTimeline)
        let seqDurMs = bridgeTimelineDurationMs(bridgeTimeline)
        let sequenceDurationFrames = msToFrames(seqDurMs, fps: seqRate)

        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })
        let urlMap = urlIndex(mediaFiles)

        var mediaToFileNum: [String: Int] = [:]
        var nextFileNum = 1
        func fileNumber(for clip: OTIOClip) -> Int {
            let key = fileDedupeKey(for: clip)
            if let n = mediaToFileNum[key] { return n }
            let n = nextFileNum
            nextFileNum += 1
            mediaToFileNum[key] = n
            return n
        }

        var embeddedKeys = Set<String>()
        var clipItemCounter = 0

        func fullFileElement(for media: MediaFile, fileNum: Int) -> String {
            let fps = media.fps
            let durFrames = msToFrames(media.durationMs, fps: fps)
            let tb = Int(round(fps))
            let ntsc = isNTSCfps(fps) ? "TRUE" : "FALSE"
            let pathURL = interchangePathURLString(forFileURL: media.url)
            return """
                          <file id="file-\(fileNum)">
                            <name>\(escapeXML(media.url.lastPathComponent))</name>
                            <pathurl>\(escapeXML(pathURL))</pathurl>
                            <duration>\(durFrames)</duration>
                            <rate>
                              <timebase>\(tb)</timebase>
                              <ntsc>\(ntsc)</ntsc>
                            </rate>
                            <media>
                              <video>
                                <samplecharacteristics>
                                  <width>\(media.width)</width>
                                  <height>\(media.height)</height>
                                  <pixelaspectratio>square</pixelaspectratio>
                                  <fielddominance>none</fielddominance>
                                </samplecharacteristics>
                              </video>
                              <audio/>
                            </media>
                          </file>
            """
        }

        func clipItemXML(
            clip: OTIOClip,
            tlStartMs: Double,
            tlEndMs: Double,
            fileXML: String,
            displayName: String,
            nativeRate: Double,
            includeVideoSourceTrack: Bool,
            includeAudioSourceTrack: Bool
        ) -> String {
            clipItemCounter += 1
            let fn = fileNumber(for: clip)
            let media = resolvedMedia(for: clip, fileMap: fileMap, urlMap: urlMap)
            let clipFps = media?.fps ?? nativeRate
            let tb = Int(round(clipFps))
            let ntsc = isNTSCfps(clipFps) ? "TRUE" : "FALSE"

            let srcInMs = clip.sourceRange.startMs
            let srcOutMs = clip.sourceRange.endMs
            guard srcOutMs > srcInMs else { return "" }

            let srcIn = msToFrames(srcInMs, fps: clipFps)
            let srcOut = msToFrames(srcOutMs, fps: clipFps)
            guard srcOut > srcIn else { return "" }

            let tlStart = msToFrames(tlStartMs, fps: seqRate)
            let tlEnd = msToFrames(tlEndMs, fps: seqRate)
            guard tlEnd > tlStart else { return "" }

            let durationFrames = media.map { msToFrames($0.durationMs, fps: $0.fps) } ?? msToFrames(srcOutMs - srcInMs, fps: clipFps)

            var videoSourceBlock = ""
            if includeVideoSourceTrack {
                videoSourceBlock = """
                            <sourcetrack>
                              <mediatype>video</mediatype>
                              <trackindex>1</trackindex>
                            </sourcetrack>
                """
            }

            var audioBlock = ""
            if includeAudioSourceTrack {
                audioBlock = """
                            <sourcetrack>
                              <mediatype>audio</mediatype>
                              <trackindex>1</trackindex>
                            </sourcetrack>
                """
            }

            let clipUUID = UUID().uuidString.uppercased()
            return """

                          <clipitem id="clipitem-\(clipItemCounter)" frameBlend="FALSE">
                            <uuid>\(clipUUID)</uuid>
                            <masterclipid>masterclip-\(fn)</masterclipid>
                            <name>\(escapeXML(displayName))</name>
                            <enabled>TRUE</enabled>
                            <duration>\(durationFrames)</duration>
                            <rate>
                              <timebase>\(tb)</timebase>
                              <ntsc>\(ntsc)</ntsc>
                            </rate>
                            <in>\(srcIn)</in>
                            <out>\(srcOut)</out>
                            <start>\(tlStart)</start>
                            <end>\(tlEnd)</end>
            \(fileXML)\(videoSourceBlock)\(audioBlock)                          </clipitem>
            """
        }

        func innerTrackXML(track: OTIOTrack, includeVideoSourceTrack: Bool, includeAudioSourceTrack: Bool) -> String {
            var inner = ""
            var timelineCursorMs = 0.0

            for item in track.children {
                switch item {
                case .gap(let gap):
                    timelineCursorMs += gap.sourceRange.durationMs
                case .clip(let clip):
                    let durMs = clip.sourceRange.durationMs
                    guard durMs > 0 else { continue }

                    let tlStartMs = timelineCursorMs
                    let tlEndMs = tlStartMs + durMs
                    timelineCursorMs = tlEndMs

                    let nativeRate = clip.sourceRange.duration.rate > 0 ? clip.sourceRange.duration.rate : seqRate

                    let key = fileDedupeKey(for: clip)
                    let fn = fileNumber(for: clip)
                    let media = resolvedMedia(for: clip, fileMap: fileMap, urlMap: urlMap)

                    let filePart: String
                    if !embeddedKeys.contains(key) {
                        embeddedKeys.insert(key)
                        if let media {
                            filePart = fullFileElement(for: media, fileNum: fn)
                        } else if !clip.mediaReference.targetURL.isEmpty {
                            filePart = orphanFileElement(
                                urlString: clip.mediaReference.targetURL,
                                name: clip.name.isEmpty ? URL(fileURLWithPath: clip.mediaReference.targetURL).lastPathComponent : clip.name,
                                fileNum: fn,
                                nativeRate: nativeRate
                            )
                        } else {
                            continue
                        }
                    } else {
                        filePart = "                          <file id=\"file-\(fn)\"/>\n"
                    }

                    let dispName: String
                    if !clip.name.isEmpty {
                        dispName = clip.name
                    } else if let media {
                        dispName = media.url.lastPathComponent
                    } else if !clip.mediaReference.targetURL.isEmpty {
                        dispName = URL(fileURLWithPath: clip.mediaReference.targetURL).lastPathComponent
                    } else {
                        dispName = "Clip"
                    }

                    inner += clipItemXML(
                        clip: clip,
                        tlStartMs: tlStartMs,
                        tlEndMs: tlEndMs,
                        fileXML: filePart,
                        displayName: dispName,
                        nativeRate: nativeRate,
                        includeVideoSourceTrack: includeVideoSourceTrack,
                        includeAudioSourceTrack: includeAudioSourceTrack
                    )
                }
            }
            return inner
        }

        var videoTrackBlocks = ""
        var audioTrackBlocks = ""

        for track in bridgeTimeline.tracks {
            switch track.kind {
            case .video:
                let inner = innerTrackXML(track: track, includeVideoSourceTrack: true, includeAudioSourceTrack: false)
                guard !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                videoTrackBlocks += "                    <track>\n\(inner)\n                    </track>\n\n"
            case .audio:
                let inner = innerTrackXML(track: track, includeVideoSourceTrack: false, includeAudioSourceTrack: true)
                guard !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                audioTrackBlocks += "                    <track>\n\(inner)\n                    </track>\n\n"
            }
        }

        let tbSeq = Int(round(seqRate))
        let ntscSeq = isNTSCfps(seqRate)

        let seqTitle = bridgeTimeline.name.isEmpty ? "\(projectName) - Abscido Edit" : bridgeTimeline.name

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="4">
          <project>
            <name>\(escapeXML(projectName))</name>
            <children>
              <sequence id="sequence-1">
                <name>\(escapeXML(seqTitle))</name>
                <duration>\(sequenceDurationFrames)</duration>
                <rate>
                  <timebase>\(tbSeq)</timebase>
                  <ntsc>\(ntscSeq ? "TRUE" : "FALSE")</ntsc>
                </rate>
                <media>
                  <video>
        \(videoTrackBlocks)      </video>
                  <audio>
        \(audioTrackBlocks)      </audio>
                </media>
              </sequence>
            </children>
          </project>
        </xmeml>
        """
    }

    /// Final Cut Pro X library interchange (subset — single storyline from primary video track).
    static func buildFCPXML(
        bridgeTimeline: OTIOTimeline,
        mediaFiles: [MediaFile],
        projectName: String
    ) throws -> String {
        guard let videoTrack = bridgeTimeline.tracks.first(where: { $0.kind == .video }) else {
            throw AbscidoError.xmlExportFailed(format: "FCPXML", reason: "No video track present.")
        }

        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })
        let urlMap = urlIndex(mediaFiles)

        let seqRate = editingRate(for: bridgeTimeline)
        let frameDur = frameDurationRational(fps: seqRate)

        let firstDims = mediaFiles.first
        let formatId = "r1"
        var resources = """
              <format id="\(formatId)" frameDuration="\(frameDur)" width="\(firstDims?.width ?? 1920)" height="\(firstDims?.height ?? 1080)"/>

        """

        var assetRefs: [String: String] = [:]
        var refCounter = 2

        func ensureAsset(for clip: OTIOClip) -> String? {
            let key = fileDedupeKey(for: clip)
            if let existing = assetRefs[key] { return existing }
            guard let media = resolvedMedia(for: clip, fileMap: fileMap, urlMap: urlMap) else {
                guard !clip.mediaReference.targetURL.isEmpty else { return nil }
                let sr = clip.sourceRange
                guard sr.durationMs > 0 else { return nil }
                let assetId = "r\(refCounter)"
                refCounter += 1
                assetRefs[key] = assetId
                let durRational = msToRationalString(sr.durationMs, fps: sr.duration.rate)
                let srcURL = interchangePathURLString(fromRawPath: clip.mediaReference.targetURL)
                resources += """
                      <asset id="\(assetId)" src="\(escapeXML(srcURL))" duration="\(durRational)" hasVideo="1" hasAudio="1"/>

                """
                return assetId
            }
            let assetId = "r\(refCounter)"
            refCounter += 1
            assetRefs[key] = assetId
            let fileURL = interchangePathURLString(forFileURL: media.url)
            let durRational = msToRationalString(media.durationMs, fps: media.fps)
            resources += """
                  <asset id="\(assetId)" src="\(escapeXML(fileURL))" duration="\(durRational)" hasVideo="1" hasAudio="1"/>

            """
            return assetId
        }

        var spine = ""
        var sequenceEndMs = 0.0
        var timelineCursorMs = 0.0

        for item in videoTrack.children {
            switch item {
            case .gap(let gap):
                timelineCursorMs += gap.sourceRange.durationMs
            case .clip(let clip):
                guard clip.sourceRange.durationMs > 0 else { continue }
                guard let assetId = ensureAsset(for: clip) else {
                    timelineCursorMs += clip.sourceRange.durationMs
                    continue
                }

                let offsetMs = timelineCursorMs
                let endMs = offsetMs + clip.sourceRange.durationMs
                sequenceEndMs = max(sequenceEndMs, endMs)
                timelineCursorMs = endMs

                let sr = clip.sourceRange
                let durationRational = msToRationalString(sr.durationMs, fps: sr.duration.rate)
                let startRational = msToRationalString(sr.startMs, fps: sr.duration.rate)
                let offsetRational = msToRationalString(offsetMs, fps: seqRate)

                spine += """
                            <asset-clip ref="\(assetId)" offset="\(offsetRational)" duration="\(durationRational)" start="\(startRational)"/>

                """
            }
        }

        let totalTimelineMs = max(sequenceEndMs, bridgeTimelineDurationMs(bridgeTimeline))
        let totalDurRational = msToRationalString(totalTimelineMs, fps: seqRate)
        let seqTitle = bridgeTimeline.name.isEmpty ? "\(projectName) - Abscido Edit" : bridgeTimeline.name

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10">
          <resources>
        \(resources)  </resources>
          <library>
            <event name="\(escapeXML(projectName))">
              <project name="\(escapeXML(seqTitle))">
                <sequence format="\(formatId)" duration="\(totalDurRational)">
                  <spine>
        \(spine)          </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>
        """
    }

    /// CMX 3600-style EDL from the first video track (Resolve / Premiere compatible subset).
    static func buildCMX3600EDL(
        bridgeTimeline: OTIOTimeline,
        mediaFiles: [MediaFile],
        projectName: String
    ) throws -> String {
        guard let videoTrack = bridgeTimeline.tracks.first(where: { $0.kind == .video }) else {
            throw AbscidoError.exportFailed(reason: "No video track for EDL export.")
        }

        let seqRate = editingRate(for: bridgeTimeline)
        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })
        let urlMap = urlIndex(mediaFiles)

        var lines: [String] = []
        lines.append("TITLE: \(String(projectName.prefix(60)))")
        lines.append("FCM: NON-DROP FRAME")
        lines.append("")

        var eventNum = 1
        var timelineCursorMs = 0.0

        for item in videoTrack.children {
            switch item {
            case .gap(let gap):
                timelineCursorMs += gap.sourceRange.durationMs
            case .clip(let clip):
                let durMs = clip.sourceRange.durationMs
                guard durMs > 0 else { continue }

                let srcInMs = clip.sourceRange.startMs
                let srcOutMs = clip.sourceRange.endMs
                let recInMs = timelineCursorMs
                let recOutMs = recInMs + durMs
                timelineCursorMs = recOutMs

                guard srcOutMs > srcInMs, recOutMs > recInMs else { continue }

                let srcIn = msToFrames(srcInMs, fps: seqRate)
                let srcOut = msToFrames(srcOutMs, fps: seqRate)
                let recIn = msToFrames(recInMs, fps: seqRate)
                let recOut = msToFrames(recOutMs, fps: seqRate)

                let dispName: String
                if let m = resolvedMedia(for: clip, fileMap: fileMap, urlMap: urlMap) {
                    dispName = m.url.lastPathComponent
                } else if !clip.mediaReference.targetURL.isEmpty {
                    dispName = URL(fileURLWithPath: clip.mediaReference.targetURL).lastPathComponent
                } else {
                    dispName = clip.name.isEmpty ? "CLIP" : clip.name
                }

                let evt = String(format: "%03d", eventNum)
                lines.append("\(evt)  AX       V     C        \(edlTimecode(frames: srcIn, fps: seqRate)) \(edlTimecode(frames: srcOut, fps: seqRate)) \(edlTimecode(frames: recIn, fps: seqRate)) \(edlTimecode(frames: recOut, fps: seqRate))")
                lines.append("* FROM CLIP NAME: \(dispName)")
                lines.append("")
                eventNum += 1
            }
        }

        guard eventNum > 1 else {
            throw AbscidoError.exportFailed(reason: "Timeline has no clips for EDL export.")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Timing / media helpers

    /// Sequence timebase for xmeml — prefer the first clip’s frame rate so Resolve/Premiere agree with trimmed ranges.
    private static func editingRate(for bridge: OTIOTimeline) -> Double {
        for track in bridge.tracks {
            for item in track.children {
                if case .clip(let clip) = item {
                    let rate = clip.sourceRange.duration.rate
                    if rate > 0 { return rate }
                }
            }
        }
        return 24
    }

    private static func bridgeTimelineDurationMs(_ bridge: OTIOTimeline) -> Double {
        bridge.tracks.map { trackDurationMs($0) }.max() ?? 0
    }

    private static func trackDurationMs(_ track: OTIOTrack) -> Double {
        track.children.reduce(0) { partial, item in
            switch item {
            case .gap(let g): return partial + g.sourceRange.durationMs
            case .clip(let c): return partial + c.sourceRange.durationMs
            }
        }
    }

    private static func interchangePathURLString(forFileURL url: URL) -> String {
        url.standardizedFileURL.absoluteString
    }

    /// Normalizes stored paths (`file:///…`, `/Volumes/…`, or bare POSIX paths) for interchange URLs.
    private static func interchangePathURLString(fromRawPath raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }
        if trimmed.hasPrefix("file:"), let u = URL(string: trimmed) {
            return u.standardizedFileURL.absoluteString
        }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.absoluteString
    }

    private static func edlTimecode(frames: Int64, fps: Double) -> String {
        let fpsInt = max(1, Int(round(fps)))
        var f = frames
        var ff = f % Int64(fpsInt)
        if ff < 0 { ff += Int64(fpsInt); f -= Int64(fpsInt) }
        f /= Int64(fpsInt)
        let s = f % 60
        f /= 60
        let m = f % 60
        let h = f / 60
        return String(format: "%02d:%02d:%02d:%02d", Int(h), Int(m), Int(s), Int(ff))
    }

    private static func urlIndex(_ mediaFiles: [MediaFile]) -> [String: MediaFile] {
        var m: [String: MediaFile] = [:]
        for f in mediaFiles {
            m[normalizeURLKey(f.url.absoluteString)] = f
        }
        return m
    }

    private static func normalizeURLKey(_ s: String) -> String {
        let u: URL
        if s.hasPrefix("file:") || s.contains("://"), let parsed = URL(string: s) {
            u = parsed
        } else {
            u = URL(fileURLWithPath: s)
        }
        return u.standardizedFileURL.absoluteString.lowercased()
    }

    private static func fileDedupeKey(for clip: OTIOClip) -> String {
        if clip.mediaFileId != 0 {
            return "abscido:\(clip.mediaFileId)"
        }
        if !clip.mediaReference.targetURL.isEmpty {
            return "url:\(normalizeURLKey(clip.mediaReference.targetURL))"
        }
        return "unknown:\(clip.name)_\(clip.sourceRange.startMs)"
    }

    private static func resolvedMedia(for clip: OTIOClip, fileMap: [Int64: MediaFile], urlMap: [String: MediaFile]) -> MediaFile? {
        if clip.mediaFileId != 0, let f = fileMap[clip.mediaFileId] { return f }
        guard !clip.mediaReference.targetURL.isEmpty else { return nil }
        return urlMap[normalizeURLKey(clip.mediaReference.targetURL)]
    }

    private static func orphanFileElement(urlString: String, name: String, fileNum: Int, nativeRate: Double) -> String {
        let tb = Int(round(nativeRate))
        let ntsc = isNTSCfps(nativeRate) ? "TRUE" : "FALSE"
        let resolvedURL = interchangePathURLString(fromRawPath: urlString)
        return """
                          <file id="file-\(fileNum)">
                            <name>\(escapeXML(name))</name>
                            <pathurl>\(escapeXML(resolvedURL))</pathurl>
                            <duration>0</duration>
                            <rate>
                              <timebase>\(tb)</timebase>
                              <ntsc>\(ntsc)</ntsc>
                            </rate>
                            <media>
                              <video>
                                <samplecharacteristics>
                                  <width>1920</width>
                                  <height>1080</height>
                                  <pixelaspectratio>square</pixelaspectratio>
                                  <fielddominance>none</fielddominance>
                                </samplecharacteristics>
                              </video>
                              <audio/>
                            </media>
                          </file>
        """
    }

    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func isNTSCfps(_ fps: Double) -> Bool {
        let ntscRates = [23.976, 29.97, 59.94]
        return ntscRates.contains { abs(fps - $0) < 0.1 }
    }
}
