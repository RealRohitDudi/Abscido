import Foundation
import OpenTimelineIO

/// Editorial interchange built from an ASWF OpenTimelineIO ``Timeline``.
///
/// Swift OpenTimelineIO does not ship Python adapter plugins (`fcp_xml`, etc.). This module implements
/// FCP 7 XML and FCPXML 1.10 by **walking the same OTIO object graph** those adapters consume, using
/// timing rules aligned with the reference [otio-fcp-adapter](https://github.com/OpenTimelineIO/otio-fcp-adapter):
/// **gaps occupy parent time but emit no clip row** — neighbor clipitems use `<start>`/`<end>` in
/// parent timeline coordinates from ``Composition.rangeOfChild(index:)`` (includes gap offsets).
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

    /// Normalized OTIO track kind (`Video` / `VIDEO` / `video` → `video`).
    private static func normalizedTrackKind(_ track: Track) -> String {
        track.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// FCP 7 XML (xmeml) — DaVinci Resolve, Premiere Pro, legacy FCP.
    static func buildFCP7XML(
        timeline: Timeline,
        mediaFiles: [MediaFile],
        projectName: String
    ) throws -> String {
        guard let stack = timeline.tracks else {
            throw AbscidoError.xmlExportFailed(format: "FCP7", reason: "Timeline has no track stack.")
        }

        let seqRate = editingRate(for: timeline)
        let seqDurSec = try timeline.duration().toSeconds()
        let sequenceDurationFrames = msToFrames(seqDurSec * 1000.0, fps: seqRate)

        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })
        let urlMap = urlIndex(mediaFiles)

        var mediaToFileNum: [String: Int] = [:]
        var nextFileNum = 1
        func fileNumber(for clip: Clip) -> Int {
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
            return """
                          <file id="file-\(fileNum)">
                            <name>\(escapeXML(media.url.lastPathComponent))</name>
                            <pathurl>\(escapeXML(media.url.absoluteString))</pathurl>
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
            clip: Clip,
            timelineRange: TimeRange,
            fileXML: String,
            displayName: String,
            nativeRate: Double,
            includeAudioSourceTrack: Bool
        ) -> String {
            clipItemCounter += 1
            let fn = fileNumber(for: clip)
            let media = resolvedMedia(for: clip, fileMap: fileMap, urlMap: urlMap)
            let clipFps = media?.fps ?? nativeRate
            let tb = Int(round(clipFps))
            let ntsc = isNTSCfps(clipFps) ? "TRUE" : "FALSE"

            guard let sr = clip.sourceRange else { return "" }
            let srcInMs = sr.startTime.toSeconds() * 1000.0
            let srcOutMs = sr.endTimeExclusive().toSeconds() * 1000.0
            let srcIn = msToFrames(srcInMs, fps: clipFps)
            let srcOut = msToFrames(srcOutMs, fps: clipFps)
            guard srcOut > srcIn else { return "" }

            let tlStartMs = timelineRange.startTime.toSeconds() * 1000.0
            let tlEndMs = timelineRange.endTimeExclusive().toSeconds() * 1000.0
            let tlStart = msToFrames(tlStartMs, fps: seqRate)
            let tlEnd = msToFrames(tlEndMs, fps: seqRate)
            guard tlEnd > tlStart else { return "" }

            let durationFrames = media.map { msToFrames($0.durationMs, fps: $0.fps) } ?? msToFrames(srcOutMs - srcInMs, fps: clipFps)

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
            \(fileXML)\(audioBlock)                          </clipitem>
            """
        }

        func innerTrackXML(track: Track, includeAudioSourceTrack: Bool) throws -> String {
            var inner = ""
            let n = track.children.count
            for i in 0..<n {
                let child = track.children[i]
                if child is Gap {
                    continue
                }
                guard let clip = child as? Clip else { continue }
                let tlRange = try track.rangeOfChild(index: i)
                let nativeRate = clip.sourceRange?.duration.rate ?? seqRate

                let key = fileDedupeKey(for: clip)
                let fn = fileNumber(for: clip)
                let media = resolvedMedia(for: clip, fileMap: fileMap, urlMap: urlMap)

                let filePart: String
                if !embeddedKeys.contains(key) {
                    embeddedKeys.insert(key)
                    if let media {
                        filePart = fullFileElement(for: media, fileNum: fn)
                    } else if let ext = clip.mediaReference as? ExternalReference,
                              let urlStr = ext.targetURL {
                        filePart = orphanFileElement(
                            urlString: urlStr,
                            name: clip.name.isEmpty ? URL(fileURLWithPath: urlStr).lastPathComponent : clip.name,
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
                } else if let ext = clip.mediaReference as? ExternalReference,
                          let urlStr = ext.targetURL {
                    dispName = URL(fileURLWithPath: urlStr).lastPathComponent
                } else {
                    dispName = "Clip"
                }

                inner += clipItemXML(
                    clip: clip,
                    timelineRange: tlRange,
                    fileXML: filePart,
                    displayName: dispName,
                    nativeRate: nativeRate,
                    includeAudioSourceTrack: includeAudioSourceTrack
                )
            }
            return inner
        }

        var videoTrackBlocks = ""
        var audioTrackBlocks = ""

        for composable in stack.children {
            guard let track = composable as? Track else { continue }
            switch normalizedTrackKind(track) {
            case "video":
                let inner = try innerTrackXML(track: track, includeAudioSourceTrack: false)
                guard !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                videoTrackBlocks += "                    <track>\n\(inner)\n                    </track>\n\n"
            case "audio":
                let inner = try innerTrackXML(track: track, includeAudioSourceTrack: true)
                guard !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                audioTrackBlocks += "                    <track>\n\(inner)\n                    </track>\n\n"
            default:
                break
            }
        }

        let tbSeq = Int(round(seqRate))
        let ntscSeq = isNTSCfps(seqRate)

        let seqTitle = timeline.name.isEmpty ? "\(projectName) - Abscido Edit" : timeline.name

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
        timeline: Timeline,
        mediaFiles: [MediaFile],
        projectName: String
    ) throws -> String {
        guard let stack = timeline.tracks else {
            throw AbscidoError.xmlExportFailed(format: "FCPXML", reason: "Timeline has no track stack.")
        }

        guard let videoTrack = stack.children.compactMap({ $0 as? Track }).first(where: { normalizedTrackKind($0) == "video" }) else {
            throw AbscidoError.xmlExportFailed(format: "FCPXML", reason: "No video track present.")
        }

        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })
        let urlMap = urlIndex(mediaFiles)

        let seqRate = editingRate(for: timeline)
        let frameDur = frameDurationRational(fps: seqRate)

        let firstDims = mediaFiles.first
        let formatId = "r1"
        var resources = """
              <format id="\(formatId)" frameDuration="\(frameDur)" width="\(firstDims?.width ?? 1920)" height="\(firstDims?.height ?? 1080)"/>

        """

        var assetRefs: [String: String] = [:]
        var refCounter = 2

        func ensureAsset(for clip: Clip) -> String? {
            let key = fileDedupeKey(for: clip)
            if let existing = assetRefs[key] { return existing }
            guard let media = resolvedMedia(for: clip, fileMap: fileMap, urlMap: urlMap) else {
                guard let ext = clip.mediaReference as? ExternalReference,
                      let urlStr = ext.targetURL,
                      let sr = clip.sourceRange else { return nil }
                let assetId = "r\(refCounter)"
                refCounter += 1
                assetRefs[key] = assetId
                let durMs = sr.duration.toSeconds() * 1000.0
                let durRational = msToRationalString(durMs, fps: sr.duration.rate)
                resources += """
                      <asset id="\(assetId)" src="\(escapeXML(urlStr))" duration="\(durRational)" hasVideo="1" hasAudio="1"/>

                """
                return assetId
            }
            let assetId = "r\(refCounter)"
            refCounter += 1
            assetRefs[key] = assetId
            let fileURL = media.url.absoluteString
            let durRational = msToRationalString(media.durationMs, fps: media.fps)
            resources += """
                  <asset id="\(assetId)" src="\(escapeXML(fileURL))" duration="\(durRational)" hasVideo="1" hasAudio="1"/>

            """
            return assetId
        }

        var spine = ""
        var sequenceEndMs = 0.0

        let n = videoTrack.children.count
        for i in 0..<n {
            let child = videoTrack.children[i]
            if child is Gap {
                continue
            }
            guard let clip = child as? Clip,
                  let sr = clip.sourceRange,
                  let assetId = ensureAsset(for: clip) else { continue }

            let tlRange = try videoTrack.rangeOfChild(index: i)
            let offsetMs = tlRange.startTime.toSeconds() * 1000.0
            let endMs = tlRange.endTimeExclusive().toSeconds() * 1000.0
            sequenceEndMs = max(sequenceEndMs, endMs)

            let durationRational = msToRationalString(sr.duration.toSeconds() * 1000.0, fps: sr.duration.rate)
            let startRational = msToRationalString(sr.startTime.toSeconds() * 1000.0, fps: sr.duration.rate)
            let offsetRational = msToRationalString(offsetMs, fps: seqRate)

            spine += """
                        <asset-clip ref="\(assetId)" offset="\(offsetRational)" duration="\(durationRational)" start="\(startRational)"/>

            """
        }

        let totalTimelineMs = max(sequenceEndMs, try timeline.duration().toSeconds() * 1000.0)
        let totalDurRational = msToRationalString(totalTimelineMs, fps: seqRate)
        let seqTitle = timeline.name.isEmpty ? "\(projectName) - Abscido Edit" : timeline.name

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

    // MARK: - Timing / media helpers

    /// Sequence timebase for xmeml — must match real clip rates (e.g. 100 fps).
    ///
    /// ``Timeline`` defaults `globalStartTime` to rate **24**; using that while clips run at 100 fps
    /// yields invalid FCP XML and DaVinci Resolve often shows an empty timeline. Prefer the first
    /// clip's `source_range` rate, then fall back to global start or 24.
    private static func editingRate(for timeline: Timeline) -> Double {
        guard let stack = timeline.tracks else { return 24 }
        var fromClip: Double?
        for composable in stack.children {
            guard let track = composable as? Track else { continue }
            for i in 0..<track.children.count {
                guard let clip = track.children[i] as? Clip,
                      let sr = clip.sourceRange,
                      sr.duration.rate > 0 else { continue }
                fromClip = sr.duration.rate
                break
            }
            if fromClip != nil { break }
        }
        if let r = fromClip, r > 0 {
            return r
        }
        if let gst = timeline.globalStartTime, gst.rate > 0 {
            return gst.rate
        }
        return 24
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

    private static func abscidoMediaFileId(_ clip: Clip) -> Int64? {
        let meta = clip.metadata
        if let v = meta["abscido_mediaFileId"] as? Int64 { return v }
        if let n = meta["abscido_mediaFileId"] as? NSNumber { return n.int64Value }
        if let s = meta["abscido_mediaFileId"] as? String { return Int64(s) }
        return nil
    }

    private static func fileDedupeKey(for clip: Clip) -> String {
        if let id = abscidoMediaFileId(clip) {
            return "abscido:\(id)"
        }
        if let ext = clip.mediaReference as? ExternalReference, let u = ext.targetURL {
            return "url:\(normalizeURLKey(u))"
        }
        return "unknown:\(ObjectIdentifier(clip).debugDescription)"
    }

    private static func resolvedMedia(for clip: Clip, fileMap: [Int64: MediaFile], urlMap: [String: MediaFile]) -> MediaFile? {
        if let id = abscidoMediaFileId(clip), let f = fileMap[id] { return f }
        guard let ext = clip.mediaReference as? ExternalReference,
              let urlStr = ext.targetURL else { return nil }
        return urlMap[normalizeURLKey(urlStr)]
    }

    private static func orphanFileElement(urlString: String, name: String, fileNum: Int, nativeRate: Double) -> String {
        let tb = Int(round(nativeRate))
        let ntsc = isNTSCfps(nativeRate) ? "TRUE" : "FALSE"
        let resolvedURL: String
        if let u = URL(string: urlString), u.scheme != nil {
            resolvedURL = u.absoluteString
        } else {
            resolvedURL = URL(fileURLWithPath: urlString).absoluteString
        }
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
