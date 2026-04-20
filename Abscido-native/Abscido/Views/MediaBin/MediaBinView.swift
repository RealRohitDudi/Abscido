import SwiftUI

/// Sidebar clip list showing imported media files.
struct MediaBinView: View {
    let mediaFiles: [MediaFile]
    @Binding var selectedId: Int64?
    var onRemove: (MediaFile) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Media Bin")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(mediaFiles.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(red: 0.18, green: 0.18, blue: 0.18))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if mediaFiles.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No media files")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Press ⌘I to import")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(mediaFiles, selection: $selectedId) { file in
                    MediaClipRow(file: file)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                onRemove(file)
                            }
                        }
                        .tag(file.id)
                }
                .listStyle(.sidebar)
            }
        }
        .background(Color(red: 0.102, green: 0.102, blue: 0.102)) // #1a1a1a
    }
}
