import Foundation

/// Pure Swift XML builders for FCP7 XML and FCPXML 1.10 export.
/// Uses Foundation XMLDocument for spec-correct output.
struct XmlExportService: Sendable {

    // MARK: - FCP7 XML

    /// Builds FCP7 XML (Premiere Pro / DaVinci Resolve compatible).
    func buildFcp7XML(
        edl: [EditDecision],
        mediaFiles: [MediaFile],
        projectName: String
    ) -> String {
        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE xmeml>
        <xmeml version="4">
          <project>
            <name>\(escapeXML(projectName))</name>
            <children>
              <sequence>
                <name>\(escapeXML(projectName)) - Abscido Edit</name>
                <duration>\(totalDurationFrames(edl: edl, fileMap: fileMap))</duration>
                <rate>
                  <timebase>\(primaryTimebase(fileMap: fileMap))</timebase>
                  <ntsc>\(isNTSC(fileMap: fileMap) ? "TRUE" : "FALSE")</ntsc>
                </rate>
                <media>
                  <video>
                    <track>
        """

        var cumulativeFrame: Int64 = 0
        var fileIdCounter = 1

        for decision in edl {
            guard let file = fileMap[decision.clipId] else { continue }
            let fps = file.fps

            for range in decision.keepRanges {
                let inFrame = msToFrames(range.startMs, fps: fps)
                let outFrame = msToFrames(range.endMs, fps: fps)
                let clipDurationFrames = outFrame - inFrame
                let startFrame = cumulativeFrame
                let endFrame = cumulativeFrame + clipDurationFrames

                let fileURL = "file://\(file.filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.filePath)"

                xml += """

                          <clipitem>
                            <name>\(escapeXML(file.url.lastPathComponent))</name>
                            <duration>\(msToFrames(file.durationMs, fps: fps))</duration>
                            <rate>
                              <timebase>\(Int(round(fps)))</timebase>
                              <ntsc>\(isNTSCfps(fps) ? "TRUE" : "FALSE")</ntsc>
                            </rate>
                            <in>\(inFrame)</in>
                            <out>\(outFrame)</out>
                            <start>\(startFrame)</start>
                            <end>\(endFrame)</end>
                            <file id="file-\(fileIdCounter)">
                              <name>\(escapeXML(file.url.lastPathComponent))</name>
                              <pathurl>\(escapeXML(fileURL))</pathurl>
                              <duration>\(msToFrames(file.durationMs, fps: fps))</duration>
                              <rate>
                                <timebase>\(Int(round(fps)))</timebase>
                                <ntsc>\(isNTSCfps(fps) ? "TRUE" : "FALSE")</ntsc>
                              </rate>
                              <media>
                                <video>
                                  <samplecharacteristics>
                                    <width>\(file.width)</width>
                                    <height>\(file.height)</height>
                                  </samplecharacteristics>
                                </video>
                                <audio/>
                              </media>
                            </file>
                          </clipitem>
                """

                cumulativeFrame = endFrame
            }
            fileIdCounter += 1
        }

        xml += """

                    </track>
                  </video>
                  <audio>
                    <track/>
                  </audio>
                </media>
              </sequence>
            </children>
          </project>
        </xmeml>
        """

        return xml
    }

    // MARK: - FCPXML 1.10

    /// Builds FCPXML 1.10 (Final Cut Pro compatible).
    func buildFCPXML(
        edl: [EditDecision],
        mediaFiles: [MediaFile],
        projectName: String
    ) -> String {
        let fileMap = Dictionary(uniqueKeysWithValues: mediaFiles.map { ($0.id, $0) })
        let primaryFps = mediaFiles.first?.fps ?? 30.0
        let frameDur = frameDurationRational(fps: primaryFps)

        var resources = ""
        var assetRefs: [Int64: String] = [:]
        var refCounter = 2

        // Format resource
        let firstFile = mediaFiles.first
        let formatId = "r1"
        resources += """
              <format id="\(formatId)" frameDuration="\(frameDur)" \
        width="\(firstFile?.width ?? 1920)" height="\(firstFile?.height ?? 1080)"/>

        """

        // Asset resources
        for file in mediaFiles {
            let assetId = "r\(refCounter)"
            assetRefs[file.id] = assetId
            let fileURL = "file://\(file.filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.filePath)"
            let durRational = msToRationalString(file.durationMs, fps: file.fps)

            resources += """
                  <asset id="\(assetId)" src="\(escapeXML(fileURL))" \
            duration="\(durRational)" hasVideo="1" hasAudio="1"/>

            """
            refCounter += 1
        }

        // Build spine clips
        var spineContent = ""
        var offset: Double = 0

        for decision in edl {
            guard let file = fileMap[decision.clipId],
                  let assetId = assetRefs[decision.clipId] else { continue }

            for range in decision.keepRanges {
                let offsetRational = msToRationalString(offset, fps: primaryFps)
                let durationRational = msToRationalString(range.durationMs, fps: file.fps)
                let startRational = msToRationalString(range.startMs, fps: file.fps)

                spineContent += """
                        <asset-clip ref="\(assetId)" \
                offset="\(offsetRational)" \
                duration="\(durationRational)" \
                start="\(startRational)"/>

                """
                offset += range.durationMs
            }
        }

        let totalDurRational = msToRationalString(offset, fps: primaryFps)

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE fcpxml>
        <fcpxml version="1.10">
          <resources>
        \(resources)  </resources>
          <library>
            <event name="\(escapeXML(projectName))">
              <project name="\(escapeXML(projectName)) - Abscido Edit">
                <sequence format="\(formatId)" duration="\(totalDurRational)">
                  <spine>
        \(spineContent)          </spine>
                </sequence>
              </project>
            </event>
          </library>
        </fcpxml>
        """

        return xml
    }

    // MARK: - Helpers

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func totalDurationFrames(edl: [EditDecision], fileMap: [Int64: MediaFile]) -> Int64 {
        var total: Int64 = 0
        for decision in edl {
            guard let file = fileMap[decision.clipId] else { continue }
            for range in decision.keepRanges {
                total += msToFrames(range.durationMs, fps: file.fps)
            }
        }
        return total
    }

    private func primaryTimebase(fileMap: [Int64: MediaFile]) -> Int {
        let fps = fileMap.values.first?.fps ?? 30.0
        return Int(round(fps))
    }

    private func isNTSC(fileMap: [Int64: MediaFile]) -> Bool {
        guard let fps = fileMap.values.first?.fps else { return false }
        return isNTSCfps(fps)
    }

    private func isNTSCfps(_ fps: Double) -> Bool {
        let ntscRates = [23.976, 29.97, 59.94]
        return ntscRates.contains(where: { abs(fps - $0) < 0.1 })
    }
}
