import SwiftUI
import Foundation

struct AlbumArtDisplay: Codable, Identifiable, Hashable {
    let id: String
    let albumName: String
    let artistName: String
    let imageURL: String? // Spotify album art URL
    var isVisible: Bool = true
    
    // Transform properties for interactive positioning
    var offsetX: CGFloat = 80   // Default to lower right within card bounds
    var offsetY: CGFloat = 120  // Default to lower right within card bounds  
    var scale: CGFloat = 0.8
    var rotationDegrees: Double = 0
    var zIndex: Double = 2 // Above songs and route by default
    
    // Computed properties for SwiftUI compatibility
    var offset: CGSize {
        get { CGSize(width: offsetX, height: offsetY) }
        set { 
            offsetX = newValue.width
            offsetY = newValue.height
        }
    }
    
    var rotation: Angle {
        get { Angle.degrees(rotationDegrees) }
        set { rotationDegrees = newValue.degrees }
    }
    
    init(albumName: String, artistName: String, imageURL: String?) {
        self.id = UUID().uuidString
        self.albumName = albumName
        self.artistName = artistName
        self.imageURL = imageURL
    }
    
    // Initializer to preserve ID when updating
    init(id: String, albumName: String, artistName: String, imageURL: String?) {
        self.id = id
        self.albumName = albumName
        self.artistName = artistName
        self.imageURL = imageURL
    }
}

// Extension to generate album art displays from tracks
extension RunActivity {
    var availableAlbumArt: [AlbumArtDisplay] {
        guard let tracks = spotifyTracks else { return [] }
        
        // Group tracks by album using a hashable key
        let albumGroups = Dictionary(grouping: tracks) { track in
            "\(track.album ?? "Unknown Album")|\(track.artist)"
        }
        
        // Only include albums with 3+ songs to make album art meaningful
        // Sort by track count (descending) then by album name, and limit to 4 albums
        return albumGroups.compactMap { (albumKey, albumTracks) in
            guard albumTracks.count >= 3 else { return nil }
            
            let components = albumKey.components(separatedBy: "|")
            let albumName = components.first ?? "Unknown Album"
            let artistName = components.count > 1 ? components[1] : "Unknown Artist"
            let imageURL = albumTracks.first?.albumImageURL
            
            return AlbumArtDisplay(
                albumName: albumName,
                artistName: artistName,
                imageURL: imageURL
            )
        }.sorted { lhs, rhs in
            // First sort by track count (descending - more tracks first)
            let lhsCount = albumGroups["\(lhs.albumName)|\(lhs.artistName)"]?.count ?? 0
            let rhsCount = albumGroups["\(rhs.albumName)|\(rhs.artistName)"]?.count ?? 0
            if lhsCount != rhsCount {
                return lhsCount > rhsCount
            }
            // Then sort by album name (ascending)
            return lhs.albumName < rhs.albumName
        }.prefix(4).map { $0 } // Limit to 4 most relevant albums
    }
    
    mutating func toggleAlbumArt(_ albumArt: AlbumArtDisplay) {
        // This would be stored in the run's album art array
        // For now, we'll add this functionality step by step
    }
}

// Transform state for interactive album art
struct AlbumArtTransforms {
    let offsetX: CGFloat
    let offsetY: CGFloat
    let scale: CGFloat
    let rotationDegrees: Double
    let zIndex: Double
    
    init(from albumArt: AlbumArtDisplay) {
        self.offsetX = albumArt.offsetX
        self.offsetY = albumArt.offsetY
        self.scale = albumArt.scale
        self.rotationDegrees = albumArt.rotationDegrees
        self.zIndex = albumArt.zIndex
    }
    
    var offset: CGSize {
        CGSize(width: offsetX, height: offsetY)
    }
    
    var rotation: Angle {
        Angle.degrees(rotationDegrees)
    }
}

// MARK: - Power Song Display Model

struct PowerSongDisplay: Codable, Identifiable, Hashable {
    let id: String
    let songName: String
    let artistName: String
    let pacePerMile: String
    var isVisible: Bool = true
    
    // Transform properties for interactive positioning - now percentage-based (0.0-1.0)
    var offsetXPercent: Double = 0.86   // 86% from left (bottom right positioning)
    var offsetYPercent: Double = 0.92   // 92% from top (adjusted higher per user feedback)
    var scale: CGFloat = 1.0
    var rotationDegrees: Double = 0
    var zIndex: Double = 3 // Above album art and route
    
    // Legacy absolute positioning properties for backward compatibility
    var offsetX: CGFloat {
        get { CGFloat(offsetXPercent * 362.0) } // Convert to absolute using standard card width
        set { offsetXPercent = Double(newValue / 362.0) } // Convert back to percentage
    }
    
    var offsetY: CGFloat {
        get { CGFloat(offsetYPercent * 595.56) } // Convert to absolute using standard card height
        set { offsetYPercent = Double(newValue / 595.56) } // Convert back to percentage
    }
    
    // Computed properties for SwiftUI compatibility
    var offset: CGSize {
        get { CGSize(width: offsetX, height: offsetY) }
        set { 
            offsetX = newValue.width
            offsetY = newValue.height
        }
    }
    
    var rotation: Angle {
        get { Angle.degrees(rotationDegrees) }
        set { rotationDegrees = newValue.degrees }
    }
    
    // Helper method to get absolute position for any card size
    func absolutePosition(cardWidth: CGFloat, cardHeight: CGFloat) -> CGPoint {
        return CGPoint(
            x: CGFloat(offsetXPercent) * cardWidth,
            y: CGFloat(offsetYPercent) * cardHeight
        )
    }
    
    // Helper method to update from absolute position
    mutating func updatePosition(x: CGFloat, y: CGFloat, cardWidth: CGFloat, cardHeight: CGFloat) {
        // Clamp the position to keep power song within card bounds
        // Adding some padding (10% margin) to prevent it from going to the very edge
        let minPercent = 0.1  // 10% from edge
        let maxPercent = 0.9  // 90% from edge
        
        offsetXPercent = Double(x / cardWidth).clamped(to: minPercent...maxPercent)
        offsetYPercent = Double(y / cardHeight).clamped(to: minPercent...maxPercent)
    }
    
    init(songName: String, artistName: String, pacePerMile: String) {
        self.id = UUID().uuidString
        self.songName = songName
        self.artistName = artistName
        self.pacePerMile = pacePerMile
    }
    
    // Initializer to preserve ID when updating
    init(id: String, songName: String, artistName: String, pacePerMile: String) {
        self.id = id
        self.songName = songName
        self.artistName = artistName
        self.pacePerMile = pacePerMile
    }
}

// MARK: - Extensions

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}