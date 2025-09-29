import SwiftUI

struct InteractiveAlbumArtView: View {
    @Binding var albumArt: AlbumArtDisplay
    let onTransformChanged: () -> Void
    
    @State private var lastOffset = CGSize.zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastRotation: Angle = .zero
    
    var body: some View {
        AsyncImage(url: URL(string: albumArt.imageURL ?? "")) { phase in
            switch phase {
            case .success(let image):
                let _ = print("🎨 ASYNC IMAGE SUCCESS: \(albumArt.albumName) image loaded successfully")
                return AnyView(
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                )
            case .failure(let error):
                let _ = print("🎨 ASYNC IMAGE FAILURE: \(albumArt.albumName) failed to load - \(error)")
                return AnyView(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.title2)
                                    .foregroundColor(.red)
                                Text("Failed")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        )
                )
            case .empty:
                let _ = print("🎨 ASYNC IMAGE LOADING: \(albumArt.albumName) is loading...")
                return AnyView(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            VStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        )
                )
            @unknown default:
                let _ = print("🎨 ASYNC IMAGE UNKNOWN STATE: \(albumArt.albumName)")
                return AnyView(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .overlay(
                            VStack(spacing: 4) {
                                Image(systemName: "music.note")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                
                                Text(albumArt.albumName)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                        )
                )
            }
        }
        .scaleEffect(albumArt.scale)
        .rotationEffect(albumArt.rotation)
        .position(x: albumArt.offsetX, y: albumArt.offsetY)
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Update position based on drag
                        albumArt.offsetX = lastOffset.width + value.translation.width
                        albumArt.offsetY = lastOffset.height + value.translation.height
                        onTransformChanged()
                    }
                    .onEnded { _ in
                        lastOffset = CGSize(width: albumArt.offsetX, height: albumArt.offsetY)
                    },
                MagnificationGesture()
                    .onChanged { value in
                        albumArt.scale = lastScale * value
                        onTransformChanged()
                    }
                    .onEnded { _ in
                        lastScale = albumArt.scale
                    }
            )
            .simultaneously(with:
                RotationGesture()
                    .onChanged { value in
                        albumArt.rotation = lastRotation + value
                        onTransformChanged()
                    }
                    .onEnded { _ in
                        lastRotation = albumArt.rotation
                    }
            )
        )
        .onTapGesture(count: 2) {
            // Double tap to reset transforms (keep position)
            withAnimation(.spring()) {
                albumArt.scale = 0.8
                albumArt.rotation = .zero
                lastScale = 0.8
                lastRotation = .zero
            }
            onTransformChanged()
        }
        .animation(.interactiveSpring(), value: albumArt.offsetX)
        .animation(.interactiveSpring(), value: albumArt.offsetY)
        .animation(.interactiveSpring(), value: albumArt.scale)
        .animation(.interactiveSpring(), value: albumArt.rotation)
        .onAppear {
            // Initialize last values from current state
            lastOffset = CGSize(width: albumArt.offsetX, height: albumArt.offsetY)
            lastScale = albumArt.scale
            lastRotation = albumArt.rotation
            print("🎨 INIT: Album art \(albumArt.albumName) initialized with position: (\(albumArt.offsetX), \(albumArt.offsetY)), scale: \(albumArt.scale), zIndex: \(albumArt.zIndex)")
            print("🎨 VISIBILITY CHECK: Album art at (\(albumArt.offsetX), \(albumArt.offsetY)) should be visible: \(albumArt.isVisible)")
            print("🎨 IMAGE URL DEBUG: \(albumArt.imageURL ?? "NO URL")")
            if let urlString = albumArt.imageURL, let url = URL(string: urlString) {
                print("🎨 URL VALIDITY CHECK: URL is valid - \(url)")
            } else {
                print("🎨 URL VALIDITY CHECK: URL is INVALID or NIL")
            }
        }
    }
}

#Preview {
    @Previewable @State var sampleAlbumArt = AlbumArtDisplay(
        albumName: "After Hours",
        artistName: "The Weeknd",
        imageURL: nil
    )
    sampleAlbumArt.isVisible = true
    
    return InteractiveAlbumArtView(albumArt: $sampleAlbumArt) {
        print("Transform changed")
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}