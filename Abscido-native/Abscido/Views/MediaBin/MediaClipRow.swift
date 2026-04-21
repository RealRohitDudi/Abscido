import SwiftUI

/// Single row in the media bin showing thumbnail, filename, duration, and resolution.
struct MediaClipRow: View {
    let file: MediaFile

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail
            Group {
                if let thumbPath = file.thumbnailPath,
                   let image = NSImage(contentsOfFile: thumbPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "film")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 56, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color(red: 0.18, green: 0.18, blue: 0.18), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.system(.body, design: .default))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(file.formattedDuration)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(file.resolution)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(file.codec.uppercased())
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .draggable(file)
    }
}
