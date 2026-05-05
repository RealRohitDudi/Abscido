import SwiftUI

/// Sidebar clip list showing imported media files.
struct MediaBinView: View {
    let mediaFiles: [MediaFile]
    @Binding var selectedId: Int64?
    var onRemove: (MediaFile) -> Void
    /// Called immediately on tap so `WorkspaceView` can load the source preview
    /// without relying on `List(selection:)` focus quirks or `onChange` timing.
    var onSelect: (MediaFile) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
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

            // MARK: Clip List
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
                GeometryReader { geo in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            LazyVStack(spacing: 2) {
                                ForEach(mediaFiles) { file in
                                    let isSelected = selectedId == file.id
                                    MediaClipRow(file: file)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(isSelected
                                                      ? Color.accentColor
                                                      : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedId = file.id
                                            onSelect(file)
                                        }
                                        .contextMenu {
                                            Button("Remove from Project", role: .destructive) {
                                                onRemove(file)
                                            }
                                        }
                                }
                            }
                            // Tappable pad below the last clip — clears selection and returns player to program.
                            let rowEstimate: CGFloat = 56
                            Color.clear
                                .contentShape(Rectangle())
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: max(48, geo.size.height - CGFloat(mediaFiles.count) * rowEstimate))
                                .onTapGesture {
                                    selectedId = nil
                                }
                        }
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    }
                }
            }
        }
        .background(Color(red: 0.102, green: 0.102, blue: 0.102))
    }
}
