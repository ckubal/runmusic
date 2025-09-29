import SwiftUI

struct PhotoBackgroundView: View {
    let photoBackground: RunPhotoBackground?
    
    var body: some View {
        GeometryReader { geometry in
            if let background = photoBackground,
               let photoData = background.photoData,
               let uiImage = UIImage(data: photoData) {
                
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(background.opacity)
                    .modifier(FilterEffectModifier(filterType: background.filterType))
                    .onAppear {
                        print("📷 PhotoBackgroundView: Rendering image \(background.photoId)")
                        print("📷   - Image size: \(uiImage.size)")
                        print("📷   - Frame size: \(geometry.size)")
                        print("📷   - Filter: \(background.filterType.displayName)")
                        print("📷   - Opacity: \(background.opacity)")
                    }
            } else {
                // Fallback when background exists but no image data
                if let background = photoBackground {
                    // Show a subtle gradient as fallback when photo data is missing
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.3),
                            Color.pink.opacity(0.2),
                            Color.purple.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .onAppear {
                        print("📷 PhotoBackgroundView: Background exists but no image data - using gradient fallback")
                        print("📷   - Photo ID: \(background.photoId)")
                        print("📷   - Photo data: \(background.photoData?.count ?? 0) bytes")
                        print("📷   - Filter: \(background.filterType)")
                    }
                } else {
                    // Always provide a visible fallback instead of Color.clear
                    LinearGradient(
                        colors: [
                            Color.gray.opacity(0.3),
                            Color.gray.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .onAppear {
                        print("📷 PhotoBackgroundView: No background provided - using gray gradient fallback")
                    }
                }
            }
        }
        .ignoresSafeArea() // Ensure image extends to edges
    }
}

struct FilterEffectModifier: ViewModifier {
    let filterType: RunPhotoBackground.PhotoFilterType
    
    func body(content: Content) -> some View {
        switch filterType {
        case .blur:
            let blackOverlay = Rectangle().fill(.black.opacity(0.2))
            content
                .blur(radius: 15)
                .overlay(blackOverlay)
                
        case .vintage:
            let vintageOverlay = Rectangle()
                .fill(LinearGradient(
                    colors: [Color.orange.opacity(0.2), Color.yellow.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            let darkenOverlay = Rectangle().fill(.black.opacity(0.25))
            
            content
                .saturation(0.8)
                .contrast(1.1)
                .brightness(-0.05)
                .overlay(vintageOverlay)
                .overlay(darkenOverlay)
                
        case .sepia:
            let sepiaOverlay = Rectangle()
                .fill(Color.brown.opacity(0.3))
                .blendMode(.multiply)
            let contrastOverlay = Rectangle().fill(.black.opacity(0.2))
            
            content
                .saturation(0.4)
                .contrast(1.2)
                .overlay(sepiaOverlay)
                .overlay(contrastOverlay)
                
        case .blackAndWhite:
            let contrastOverlay = Rectangle().fill(.black.opacity(0.3))
            
            content
                .saturation(0.0)
                .contrast(1.3)
                .brightness(0.05)
                .overlay(contrastOverlay)
                
        case .highContrast:
            let vignette = RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.4)],
                center: .center,
                startRadius: 150,
                endRadius: 400
            )
            
            content
                .contrast(1.5)
                .saturation(1.2)
                .brightness(0.1)
                .overlay(Rectangle().fill(vignette))
                
        case .cinematic:
            let letterboxTop = Rectangle().fill(.black)
                .frame(height: 40)
                .frame(maxWidth: .infinity)
            let letterboxBottom = Rectangle().fill(.black)
                .frame(height: 40)
                .frame(maxWidth: .infinity)
            let tint = Rectangle().fill(Color.blue.opacity(0.1))
            
            content
                .contrast(1.2)
                .saturation(0.9)
                .overlay(tint)
                .overlay(VStack {
                    letterboxTop
                    Spacer()
                    letterboxBottom
                })
                
        case .softFocus:
            let dreamyOverlay = Rectangle()
                .fill(.white.opacity(0.15))
                .blendMode(.softLight)
            
            content
                .blur(radius: 4)
                .brightness(0.08)
                .saturation(0.9)
                .overlay(dreamyOverlay)
        }
    }
}

// MARK: - Track List

struct ShareableTrackList: View {
    let tracks: [SpotifyTrack] // Visible tracks to display
    let allTracks: [SpotifyTrack]? // All tracks from the run (for total count)
    let fontFamily: FontFamily
    let powerSong: SpotifyTrack? // The power song to highlight
    let maxTracks: Int = 10 // Max 10 tracks on shareable card
    
    // Sort tracks chronologically (earliest first)
    private var sortedTracks: [SpotifyTrack] {
        tracks.sorted { $0.playedAt < $1.playedAt }
    }
    
    // Initialize with tracks and font
    init(tracks: [SpotifyTrack], allTracks: [SpotifyTrack]? = nil, fontFamily: FontFamily = FontFamily.default, powerSong: SpotifyTrack? = nil) {
        self.tracks = tracks
        self.allTracks = allTracks
        self.fontFamily = fontFamily
        self.powerSong = powerSong
    }
    
    var body: some View {
        let displayTracks = Array(sortedTracks.prefix(maxTracks))
        let indexedTracks = Array(displayTracks.enumerated())
        
        return HStack {
            VStack(alignment: .leading, spacing: 2) { // Even tighter spacing
                ForEach(indexedTracks, id: \.offset) { index, track in
                    ShareableTrackRow(track: track, index: index + 1, fontFamily: fontFamily, isPowerSong: powerSong?.id == track.id) // Pass 1-based index and power song status
                }
                
                // Calculate remaining songs based on total tracks from run, not just visible tracks
                let totalTracksFromRun = allTracks?.count ?? sortedTracks.count
                let remainingSongs = totalTracksFromRun - displayTracks.count
                if remainingSongs > 0 {
                    HStack {
                        Text("+\(remainingSongs) other \(remainingSongs == 1 ? "song" : "songs")")
                            .font(fontFamily.customFont(size: 10))
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(0) // Hard corners
                        
                        Spacer()
                    }
                }
            }
            .padding(.leading, 30) // 30px from left edge
            
            Spacer() // Allow content to extend to the right
        }
    }
}


// MARK: - Photo Filter Selection View

struct PhotoFilterSelectionView: View {
    let photoData: Data
    @Binding var selectedFilter: RunPhotoBackground.PhotoFilterType
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("photo effects")
                .font(.custom("Helvetica Neue", size: 18))
                .fontWeight(.semibold)
            
            // Filter options - horizontal scrolling for better mobile UX
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(RunPhotoBackground.PhotoFilterType.allCases, id: \.self) { filterType in
                        FilterPreviewCard(
                            photoData: photoData,
                            filterType: filterType,
                            isSelected: selectedFilter == filterType,
                            onTap: {
                                selectedFilter = filterType
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            
        }
    }
}

struct FilterPreviewCard: View {
    let photoData: Data
    let filterType: RunPhotoBackground.PhotoFilterType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                // Preview image with filter - optimized for horizontal scrolling
                if let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipped()
                        .modifier(FilterEffectModifier(filterType: filterType))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isSelected ? Color.orange : Color.gray.opacity(0.3),
                                    lineWidth: isSelected ? 3 : 1
                                )
                        )
                }
                
                Text(filterType.displayName)
                    .font(.custom("Helvetica Neue", size: 11))
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .orange : .primary)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack {
        ShareableTrackList(tracks: [
            SpotifyTrack(id: "1", name: "Blinding Lights", artist: "The Weeknd", album: "After Hours", playedAt: Date(), durationMs: 200040, albumImageURL: nil),
            SpotifyTrack(id: "2", name: "Good 4 U", artist: "Olivia Rodrigo", album: "SOUR", playedAt: Date(), durationMs: 178320, albumImageURL: nil)
        ])
        .padding()
    }
    .background(Color.black)
}