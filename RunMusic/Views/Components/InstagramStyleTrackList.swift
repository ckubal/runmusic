import SwiftUI

struct InstagramStyleTrackList: View {
    let tracks: [SpotifyTrack]
    let allTracks: [SpotifyTrack] 
    let fontFamily: FontFamily
    let powerSong: SpotifyTrack?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(tracks.enumerated()), id: \.offset) { index, track in
                let isPowerSong = powerSong?.id == track.id
                InstagramStyleTrackRow(
                    track: track,
                    index: index + 1,
                    fontFamily: fontFamily,
                    isPowerSong: isPowerSong
                )
            }
            
            // Show "+N other songs" if there are hidden tracks
            let hiddenCount = allTracks.count - tracks.count
            if hiddenCount > 0 {
                HStack(spacing: 6) {
                    Text("+\(hiddenCount) other songs")
                        .font(fontFamily.customFont(size: 10))
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.5))
                .cornerRadius(0) // Hard corners for Instagram style
            }
        }
    }
}

#Preview {
    let sampleTracks = [
        SpotifyTrack(id: "1", name: "Sample Song", artist: "Sample Artist", playedAt: Date(), albumImageURL: nil, isVisible: true),
        SpotifyTrack(id: "2", name: "Another Song", artist: "Another Artist", playedAt: Date(), albumImageURL: nil, isVisible: true)
    ]
    
    InstagramStyleTrackList(
        tracks: sampleTracks,
        allTracks: sampleTracks,
        fontFamily: .helveticaNeue,
        powerSong: sampleTracks.first
    )
}