import Foundation
import OpenTimelineIO

// MARK: - Bridge between real OpenTimelineIO types and Abscido internal types
// These lightweight Sendable structs mirror the OTIO data for use in UI and Codable contexts.
// The OTIOEngine converts between real OTIO objects and these bridge types.

struct OTIOTime: Codable, Equatable, Sendable {
    var value: Double
    var rate: Double

    var seconds: Double {
        rate > 0 ? value / rate : 0
    }

    var milliseconds: Double {
        seconds * 1000.0
    }

    static var zero: OTIOTime {
        OTIOTime(value: 0, rate: 1)
    }

    static func fromMs(_ ms: Double, rate: Double) -> OTIOTime {
        OTIOTime(value: ms / 1000.0 * rate, rate: rate)
    }

    /// Convert to real OTIO RationalTime.
    func toRationalTime() -> RationalTime {
        RationalTime(value: value, rate: rate)
    }

    /// Create from real OTIO RationalTime.
    static func from(_ rt: RationalTime) -> OTIOTime {
        OTIOTime(value: rt.value, rate: rt.rate)
    }
}

struct OTIOTimeRange: Codable, Equatable, Sendable {
    var startTime: OTIOTime
    var duration: OTIOTime

    var endTime: OTIOTime {
        OTIOTime(value: startTime.value + duration.value, rate: startTime.rate)
    }

    var startMs: Double { startTime.milliseconds }
    var endMs: Double { endTime.milliseconds }
    var durationMs: Double { duration.milliseconds }

    /// Convert to real OTIO TimeRange.
    func toTimeRange() -> OpenTimelineIO.TimeRange {
        OpenTimelineIO.TimeRange(
            startTime: startTime.toRationalTime(),
            duration: duration.toRationalTime()
        )
    }

    /// Create from real OTIO TimeRange.
    static func from(_ tr: OpenTimelineIO.TimeRange) -> OTIOTimeRange {
        OTIOTimeRange(
            startTime: OTIOTime.from(tr.startTime),
            duration: OTIOTime.from(tr.duration)
        )
    }
}

struct OTIOMediaReference: Codable, Equatable, Sendable {
    var targetURL: String
}

struct OTIOClip: Codable, Equatable, Sendable {
    var name: String
    var mediaReference: OTIOMediaReference
    var sourceRange: OTIOTimeRange
    var mediaFileId: Int64
    var linkGroupId: String?
}

struct OTIOGap: Codable, Equatable, Sendable {
    var sourceRange: OTIOTimeRange
}

enum OTIOItem: Codable, Equatable, Sendable {
    case clip(OTIOClip)
    case gap(OTIOGap)

    enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clip(let clip):
            try container.encode("Clip", forKey: .type)
            try container.encode(clip, forKey: .data)
        case .gap(let gap):
            try container.encode("Gap", forKey: .type)
            try container.encode(gap, forKey: .data)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Clip":
            self = .clip(try container.decode(OTIOClip.self, forKey: .data))
        case "Gap":
            self = .gap(try container.decode(OTIOGap.self, forKey: .data))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container,
                debugDescription: "Unknown OTIO item type: \(type)"
            )
        }
    }
}

enum OTIOTrackKind: String, Codable, Sendable {
    case video = "Video"
    case audio = "Audio"
}

struct OTIOTrack: Codable, Equatable, Sendable {
    var name: String
    var kind: OTIOTrackKind
    var children: [OTIOItem]

    /// Total duration of all items in the track.
    var duration: OTIOTime {
        var totalValue: Double = 0
        var rate: Double = 24
        for child in children {
            switch child {
            case .clip(let clip):
                totalValue += clip.sourceRange.duration.value
                rate = clip.sourceRange.duration.rate
            case .gap(let gap):
                totalValue += gap.sourceRange.duration.value
                rate = gap.sourceRange.duration.rate
            }
        }
        return OTIOTime(value: totalValue, rate: rate)
    }

    /// All clips in order (gaps filtered out).
    var clips: [OTIOClip] {
        children.compactMap { item in
            if case .clip(let c) = item { return c } else { return nil }
        }
    }
}

struct OTIOTimeline: Codable, Equatable, Sendable {
    var name: String
    var tracks: [OTIOTrack]

    /// Total duration is the max duration across all tracks.
    var duration: OTIOTime {
        tracks.map(\.duration).max(by: { $0.value < $1.value }) ?? .zero
    }
}

// MARK: - Conversion to/from real OTIO types

extension OTIOTimeline {
    /// Converts this bridge timeline to a real OpenTimelineIO Timeline object.
    func toOTIOTimeline() -> OpenTimelineIO.Timeline {
        let otioTimeline = OpenTimelineIO.Timeline(name: name)

        for track in tracks {
            let otioTrack = OpenTimelineIO.Track(
                name: track.name,
                kind: track.kind == .video ? .video : .audio
            )

            for child in track.children {
                switch child {
                case .clip(let clipData):
                    let extRef = ExternalReference(targetURL: clipData.mediaReference.targetURL)
                    let otioClip = OpenTimelineIO.Clip(
                        name: clipData.name,
                        mediaReference: extRef,
                        sourceRange: clipData.sourceRange.toTimeRange()
                    )
                    // Store custom metadata for mediaFileId and linkGroupId
                    otioClip.metadata["abscido_mediaFileId"] = Int64(clipData.mediaFileId)
                    if let lgId = clipData.linkGroupId {
                        otioClip.metadata["abscido_linkGroupId"] = lgId
                    }
                    try? otioTrack.append(child: otioClip)

                case .gap(let gapData):
                    let otioGap = OpenTimelineIO.Gap(sourceRange: gapData.sourceRange.toTimeRange())
                    try? otioTrack.append(child: otioGap)
                }
            }

            if let stack = otioTimeline.tracks {
                try? stack.append(child: otioTrack)
            }
        }

        return otioTimeline
    }

    /// Creates a bridge timeline from a real OpenTimelineIO Timeline object.
    static func from(_ otioTimeline: OpenTimelineIO.Timeline) -> OTIOTimeline {
        var bridgeTracks: [OTIOTrack] = []

        if let stack = otioTimeline.tracks {
            for child in stack.children {
                guard let track = child as? OpenTimelineIO.Track else { continue }

                let kind: OTIOTrackKind = track.kind == "Audio" ? .audio : .video
                var bridgeChildren: [OTIOItem] = []

                for item in track.children {
                    if let clip = item as? OpenTimelineIO.Clip {
                        let mediaRef: OTIOMediaReference
                        if let extRef = clip.mediaReference as? ExternalReference {
                            mediaRef = OTIOMediaReference(targetURL: extRef.targetURL ?? "")
                        } else {
                            mediaRef = OTIOMediaReference(targetURL: "")
                        }

                        let sourceRange: OTIOTimeRange
                        if let sr = clip.sourceRange {
                            sourceRange = OTIOTimeRange.from(sr)
                        } else {
                            sourceRange = OTIOTimeRange(startTime: .zero, duration: .zero)
                        }

                        var mediaFileId: Int64 = 0
                        if let id = clip.metadata["abscido_mediaFileId"] as? Int64 {
                            mediaFileId = id
                        }

                        var linkGroupId: String?
                        if let lgId = clip.metadata["abscido_linkGroupId"] as? String {
                            linkGroupId = lgId
                        }

                        bridgeChildren.append(.clip(OTIOClip(
                            name: clip.name,
                            mediaReference: mediaRef,
                            sourceRange: sourceRange,
                            mediaFileId: mediaFileId,
                            linkGroupId: linkGroupId
                        )))

                    } else if let gap = item as? OpenTimelineIO.Gap {
                        let sourceRange: OTIOTimeRange
                        if let sr = gap.sourceRange {
                            sourceRange = OTIOTimeRange.from(sr)
                        } else {
                            sourceRange = OTIOTimeRange(startTime: .zero, duration: .zero)
                        }
                        bridgeChildren.append(.gap(OTIOGap(sourceRange: sourceRange)))
                    }
                }

                bridgeTracks.append(OTIOTrack(
                    name: track.name,
                    kind: kind,
                    children: bridgeChildren
                ))
            }
        }

        return OTIOTimeline(name: otioTimeline.name, tracks: bridgeTracks)
    }
}
