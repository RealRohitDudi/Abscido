import Foundation

// MARK: - OTIO-compatible native Swift types
// These mirror OpenTimelineIO's data model and serialize to OTIO-compatible JSON.
// When OTIO Swift bindings are available, these can be replaced with the real types.

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
}

struct OTIOMediaReference: Codable, Equatable, Sendable {
    var targetURL: String
}

struct OTIOClip: Codable, Equatable, Sendable {
    var name: String
    var mediaReference: OTIOMediaReference
    var sourceRange: OTIOTimeRange
    var mediaFileId: Int64
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
