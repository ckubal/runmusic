import SwiftUI
import Foundation

// MARK: - Font.Weight Codable Conformance

extension Font.Weight: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Double.self)
        
        switch rawValue {
        case -0.8: self = .ultraLight
        case -0.6: self = .thin
        case -0.4: self = .light
        case 0.0: self = .regular
        case 0.23: self = .medium
        case 0.3: self = .semibold
        case 0.4: self = .bold
        case 0.56: self = .heavy
        case 0.62: self = .black
        default: self = .regular
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        let rawValue: Double
        switch self {
        case .ultraLight: rawValue = -0.8
        case .thin: rawValue = -0.6
        case .light: rawValue = -0.4
        case .regular: rawValue = 0.0
        case .medium: rawValue = 0.23
        case .semibold: rawValue = 0.3
        case .bold: rawValue = 0.4
        case .heavy: rawValue = 0.56
        case .black: rawValue = 0.62
        default: rawValue = 0.0
        }
        
        try container.encode(rawValue)
    }
}

// MARK: - WeatherCondition Emoji Extension

extension WeatherData.WeatherCondition {
    var emoji: String {
        switch self {
        case .clear: return "☀️"
        case .cloudy: return "☁️"
        case .rain: return "🌧️"
        case .snow: return "🌨️"
        case .fog: return "🌫️"
        case .thunderstorm: return "⛈️"
        case .unknown: return "🌤️"
        }
    }
}

// MARK: - Color Codable Conformance

extension Color: Codable {
    enum CodingKeys: String, CodingKey {
        case red, green, blue, alpha
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let red = try container.decode(Double.self, forKey: .red)
        let green = try container.decode(Double.self, forKey: .green)
        let blue = try container.decode(Double.self, forKey: .blue)
        let alpha = try container.decode(Double.self, forKey: .alpha)
        
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Convert SwiftUI Color to UIColor to extract RGB components
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        
        try container.encode(Double(red), forKey: .red)
        try container.encode(Double(green), forKey: .green)
        try container.encode(Double(blue), forKey: .blue)
        try container.encode(Double(alpha), forKey: .alpha)
    }
}

// MARK: - Canvas Alignment (Edge-based positioning)

enum CanvasAlignment: String, Codable, CaseIterable {
    case center = "center"
    case topLeading = "topLeading"
    case top = "top"
    case topTrailing = "topTrailing"
    case leading = "leading"
    case trailing = "trailing"
    case bottomLeading = "bottomLeading"
    case bottom = "bottom"
    case bottomTrailing = "bottomTrailing"
    
    // Convert to SwiftUI Alignment
    var swiftUIAlignment: Alignment {
        switch self {
        case .center: return .center
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .leading: return .leading
        case .trailing: return .trailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

// MARK: - Canvas Asset for Run Details Canvas View

struct CanvasAsset: Identifiable, Equatable, Codable {
    let id = UUID()
    var type: AssetType
    var content: AssetContent
    var position: CGPoint
    var anchorPoint: CGPoint? // Percentage-based positioning (0.0-1.0)
    var alignment: CanvasAlignment? // SwiftUI edge-based alignment
    var rotation: Double = 0
    var scale: Double = 1.0
    var fontSize: CGFloat = 16
    var fontWeight: Font.Weight = .regular
    var fontFamily: String? = nil
    var color: Color = .white
    var showBlackOutline: Bool = false
    var isVisible: Bool = true
    var isSelected: Bool = false
    var zIndex: Double = 1.0
    
    // Editable configuration
    var editableType: EditableType = .none
    var canDelete: Bool = true
    var canDuplicate: Bool = false
    
    // Custom coding for UUID and complex types
    enum CodingKeys: String, CodingKey {
        case type, content, position, anchorPoint, alignment, rotation, scale, fontSize, fontWeight, fontFamily, color, showBlackOutline
        case isVisible, isSelected, zIndex, editableType, canDelete, canDuplicate
    }
    
    static func == (lhs: CanvasAsset, rhs: CanvasAsset) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Asset Types

enum AssetType: String, Codable, CaseIterable {
    // Basic types (from RunTunes)
    case text
    case image
    
    // RunMusic-specific types
    case titleDistance      // Combined run title + mileage display
    case route             // Interactive route visualization
    case songList          // Spotify track list
    case pace              // Pace stat with edit capability
    case date              // Date display with edit capability
    case time              // Duration display
    case weather           // Weather + temperature display
    case powerSong         // Power song highlight
    case albumArt          // Album cover art
    case location          // Location/city display
    case stats             // Combined stats cluster
    
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .image: return "Image"
        case .titleDistance: return "Title & Distance"
        case .route: return "Route Map"
        case .songList: return "Song List"
        case .pace: return "Pace"
        case .date: return "Date"
        case .time: return "Time"
        case .weather: return "Weather"
        case .powerSong: return "Power Song"
        case .albumArt: return "Album Art"
        case .location: return "Location"
        case .stats: return "Stats"
        }
    }
    
    var systemIcon: String {
        switch self {
        case .text: return "textformat"
        case .image: return "photo"
        case .titleDistance: return "textformat.size"
        case .route: return "map"
        case .songList: return "music.note.list"
        case .pace: return "speedometer"
        case .date: return "calendar"
        case .time: return "clock"
        case .weather: return "thermometer"
        case .powerSong: return "flame"
        case .albumArt: return "square.stack"
        case .location: return "location"
        case .stats: return "chart.bar"
        }
    }
}

// MARK: - Editable Types

enum EditableType: String, Codable {
    case none              // Display only, no editing
    case text              // Text editing (keyboard input)
    case visual            // Drag/scale/rotate only
    case list              // Show/hide list items, reorder
    case stat              // Edit stat values (pace, distance, etc.)
    case date              // Date picker
    case weather           // Weather/location editing
    case powerSong         // Power song management (select different song)
    case image             // Image selection/editing
    
    var displayName: String {
        switch self {
        case .none: return "View Only"
        case .text: return "Edit Text"
        case .visual: return "Move & Scale"
        case .list: return "Edit List"
        case .stat: return "Edit Value"
        case .date: return "Edit Date"
        case .weather: return "Edit Weather"
        case .powerSong: return "Edit Power Song"
        case .image: return "Edit Image"
        }
    }
}

// MARK: - Asset Content

enum AssetContent: Codable, Equatable {
    // Basic content types
    case text(String)
    case image(Data?)
    
    // RunMusic-specific content types
    case titleDistance(title: String, distance: Double, unit: String)
    case route(coordinates: [LocationData])
    case songList(tracks: [SpotifyTrack], powerSongId: String?)
    case pace(value: Double, unit: String) // seconds per km/mile
    case date(Date)
    case time(TimeInterval) // duration in seconds
    case weather(WeatherData)
    case powerSong(SpotifyTrack, pace: String?)
    case albumArt(imageURL: String?, imageData: Data?, albumName: String, artistName: String)
    case location(String)
    case stats(StatsCluster)
    
    // Helper computed properties
    var displayText: String {
        switch self {
        case .text(let string):
            return string
        case .image(_):
            return "Image"
        case .titleDistance(let title, let distance, let unit):
            return "\(String(format: "%.1f", distance)) \(unit)\n\(title)"
        case .route(_):
            return "Route Map"
        case .songList(let tracks, _):
            return "\(tracks.count) songs"
        case .pace(let value, let unit):
            let minutes = Int(value / 60)
            let seconds = Int(value.truncatingRemainder(dividingBy: 60))
            return String(format: "%d:%02d/%s", minutes, seconds, unit)
        case .date(let date):
            let formatter = DateFormatter()
            formatter.dateFormat = "E MMM d" // E = day of week abbreviation (e.g., "Sat Oct 19")
            return formatter.string(from: date).lowercased()
        case .time(let duration):
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            if hours > 0 {
                return String(format: "%d:%02d:%02d", hours, minutes, seconds)
            } else {
                return String(format: "%d:%02d", minutes, seconds)
            }
        case .weather(let weather):
            return "\(Int(weather.temperature))°F \(weather.condition.emoji)"
        case .powerSong(let track, let pace):
            if let pace = pace {
                return "🔥 \(track.name)\n\(pace)/mi"
            } else {
                return "🔥 \(track.name)"
            }
        case .albumArt(_, _, let albumName, _):
            return albumName
        case .location(let location):
            return location
        case .stats(let stats):
            return "Stats"
        }
    }
    
    // Manual Equatable implementation for complex types
    static func == (lhs: AssetContent, rhs: AssetContent) -> Bool {
        switch (lhs, rhs) {
        case (.text(let lhsString), .text(let rhsString)):
            return lhsString == rhsString
        case (.image(let lhsData), .image(let rhsData)):
            return lhsData == rhsData
        case (.titleDistance(let lhsTitle, let lhsDistance, let lhsUnit), 
              .titleDistance(let rhsTitle, let rhsDistance, let rhsUnit)):
            return lhsTitle == rhsTitle && lhsDistance == rhsDistance && lhsUnit == rhsUnit
        case (.route(let lhsCoords), .route(let rhsCoords)):
            return lhsCoords.count == rhsCoords.count // Simplified comparison
        case (.songList(let lhsTracks, let lhsPowerSongId), .songList(let rhsTracks, let rhsPowerSongId)):
            return lhsTracks.count == rhsTracks.count && lhsPowerSongId == rhsPowerSongId
        case (.pace(let lhsValue, let lhsUnit), .pace(let rhsValue, let rhsUnit)):
            return lhsValue == rhsValue && lhsUnit == rhsUnit
        case (.date(let lhsDate), .date(let rhsDate)):
            return lhsDate == rhsDate
        case (.time(let lhsTime), .time(let rhsTime)):
            return lhsTime == rhsTime
        case (.weather(let lhsWeather), .weather(let rhsWeather)):
            return lhsWeather.temperature == rhsWeather.temperature && lhsWeather.condition == rhsWeather.condition
        case (.powerSong(let lhsTrack, let lhsPace), .powerSong(let rhsTrack, let rhsPace)):
            return lhsTrack.id == rhsTrack.id && lhsPace == rhsPace
        case (.albumArt(let lhsURL, _, let lhsAlbum, let lhsArtist), 
              .albumArt(let rhsURL, _, let rhsAlbum, let rhsArtist)):
            return lhsURL == rhsURL && lhsAlbum == rhsAlbum && lhsArtist == rhsArtist
        case (.location(let lhsLocation), .location(let rhsLocation)):
            return lhsLocation == rhsLocation
        case (.stats(let lhsStats), .stats(let rhsStats)):
            return lhsStats == rhsStats
        default:
            return false
        }
    }
}

// MARK: - Supporting Models

struct StatsCluster: Codable, Equatable {
    let pace: String
    let date: String
    let time: String
    let weather: String?
    
    init(run: RunActivity) {
        // Convert RunActivity to display strings
        self.pace = UserPreferences.shared.formatPace(run.averagePace) + "/\(UserPreferences.shared.distanceUnit.abbreviation)"
        
        let formatter = DateFormatter()
        formatter.dateFormat = "E MMM d" // E = day of week abbreviation (e.g., "Sat Oct 19")
        self.date = formatter.string(from: run.date).lowercased()
        
        self.time = run.formattedDuration
        
        if let weather = run.weatherData {
            self.weather = "\(Int(weather.temperature))°F \(weather.condition.emoji)"
        } else {
            self.weather = nil
        }
    }
}


// MARK: - Asset Factory

extension CanvasAsset {
    
    // MARK: - Factory Methods for RunMusic Assets
    
    static func createTitleDistance(for run: RunActivity, position: CGPoint = CGPoint(x: 200, y: 100)) -> CanvasAsset {
        let distance = UserPreferences.shared.formatDistance(run.distance)
        let unit = UserPreferences.shared.distanceUnit.abbreviation.lowercased()
        
        return CanvasAsset(
            type: .titleDistance,
            content: .titleDistance(title: run.name, distance: Double(distance) ?? 0, unit: unit),
            position: position,
            fontSize: 32,
            fontWeight: .bold,
            editableType: .text,
            canDelete: false // Core element, can't be deleted
        )
    }
    
    static func createRoute(for run: RunActivity, position: CGPoint = CGPoint(x: 200, y: 250)) -> CanvasAsset {
        return CanvasAsset(
            type: .route,
            content: .route(coordinates: run.routeCoordinates),
            position: position,
            scale: 0.8,
            editableType: .visual,
            canDelete: false
        )
    }
    
    static func createSongList(for run: RunActivity, position: CGPoint = CGPoint(x: 40, y: 350)) -> CanvasAsset {
        var tracks = run.spotifyTracks ?? []
        let powerSongId = run.powerSong?.id
        
        // CRITICAL FIX: If we have no tracks but have a power song, include the power song
        if tracks.isEmpty, let powerSong = run.powerSong {
            tracks = [powerSong]
        }
        
        // Default to showing up to 20 songs (all tracks from run)
        tracks = Array(tracks.prefix(20))
        
        return CanvasAsset(
            type: .songList,
            content: .songList(tracks: tracks, powerSongId: powerSongId),
            position: position,
            fontSize: 12,
            fontWeight: .medium,
            color: .white,
            showBlackOutline: true, // Enable by default
            editableType: .list,
            canDelete: tracks.isEmpty // Can delete if no songs
        )
    }
    
    static func createCompactSongList(for run: RunActivity, position: CGPoint, maxSongs: Int = 6) -> CanvasAsset {
        var tracks = run.spotifyTracks ?? []
        let powerSongId = run.powerSong?.id
        
        // CRITICAL FIX: If we have no tracks but have a power song, include the power song
        if tracks.isEmpty, let powerSong = run.powerSong {
            tracks = [powerSong]
        }
        
        // Limit to specified max to prevent layout overflow
        tracks = Array(tracks.prefix(maxSongs))
        
        return CanvasAsset(
            type: .songList,
            content: .songList(tracks: tracks, powerSongId: powerSongId),
            position: position,
            fontSize: 11, // Slightly smaller for compact layout
            fontWeight: .medium,
            color: .white,
            showBlackOutline: true,
            editableType: .list,
            canDelete: tracks.isEmpty
        )
    }
    
    static func createPace(for run: RunActivity, position: CGPoint = CGPoint(x: 50, y: 50)) -> CanvasAsset {
        let unit = UserPreferences.shared.distanceUnit == .miles ? "mi" : "km"
        return CanvasAsset(
            type: .pace,
            content: .pace(value: run.averagePace, unit: unit),
            position: position,
            fontSize: 14,
            fontWeight: .semibold,
            color: .green,
            editableType: .stat
        )
    }
    
    static func createDate(for run: RunActivity, position: CGPoint = CGPoint(x: 150, y: 50)) -> CanvasAsset {
        return CanvasAsset(
            type: .date,
            content: .date(run.date),
            position: position,
            fontSize: 12,
            fontWeight: .medium,
            color: .gray,
            editableType: .date
        )
    }
    
    static func createTime(for run: RunActivity, position: CGPoint = CGPoint(x: 250, y: 50)) -> CanvasAsset {
        return CanvasAsset(
            type: .time,
            content: .time(run.elapsedTime),
            position: position,
            fontSize: 14,
            fontWeight: .semibold,
            color: .blue,
            editableType: .none
        )
    }
    
    static func createWeather(for run: RunActivity, position: CGPoint = CGPoint(x: 350, y: 50)) -> CanvasAsset? {
        guard let weather = run.weatherData else { return nil }
        
        return CanvasAsset(
            type: .weather,
            content: .weather(weather),
            position: position,
            fontSize: 12,
            fontWeight: .medium,
            color: .orange,
            editableType: .weather
        )
    }
    
    static func createPowerSong(for run: RunActivity, position: CGPoint = CGPoint(x: 320, y: 450)) -> CanvasAsset? {
        // If we have a proper power song, use it
        if let powerSong = run.powerSong {
            return CanvasAsset(
                type: .powerSong,
                content: .powerSong(powerSong, pace: run.powerSongPacePerMile),
                position: position,
                fontSize: 14,
                fontWeight: .bold,
                color: .red,
                zIndex: 2.0,
                editableType: .powerSong
            )
        }
        
        // FALLBACK: If no power song but we have Spotify tracks, use the first one as power song
        if let firstTrack = run.spotifyTracks?.first {
            return CanvasAsset(
                type: .powerSong,
                content: .powerSong(firstTrack, pace: nil),
                position: position,
                fontSize: 14,
                fontWeight: .bold,
                color: .red,
                zIndex: 2.0,
                editableType: .powerSong
            )
        }
        
        return nil
    }
    
    static func createAlbumArt(imageURL: String?, imageData: Data?, albumName: String, artistName: String, position: CGPoint, anchorPoint: CGPoint? = nil) -> CanvasAsset {
        return CanvasAsset(
            type: .albumArt,
            content: .albumArt(imageURL: imageURL, imageData: imageData, albumName: albumName, artistName: artistName),
            position: position,
            anchorPoint: anchorPoint, // Set directly during creation
            alignment: nil,   // Use percentage positioning
            scale: 0.6,
            zIndex: 1.5,
            editableType: .visual
        )
    }
    
    static func createLocation(for run: RunActivity, position: CGPoint = CGPoint(x: 200, y: 150)) -> CanvasAsset? {
        // Try smart location display first
        if let location = run.smartLocationDisplay {
            return CanvasAsset(
                type: .location,
                content: .location(location),
                position: position,
                fontSize: 12,
                fontWeight: .medium,
                color: .orange,
                editableType: .text
            )
        }
        
        // FALLBACK: Try city if available
        if let city = run.city, !city.isEmpty {
            return CanvasAsset(
                type: .location,
                content: .location(city),
                position: position,
                fontSize: 12,
                fontWeight: .medium,
                color: .orange,
                editableType: .text
            )
        }
        
        // FALLBACK: Use generic location if no specific location available
        return CanvasAsset(
            type: .location,
            content: .location("unknown location"),
            position: position,
            fontSize: 12,
            fontWeight: .medium,
            color: .orange.opacity(0.7),
            editableType: .text
        )
    }
    
    static func createStatsCluster(for run: RunActivity, position: CGPoint = CGPoint(x: 300, y: 100)) -> CanvasAsset {
        let stats = StatsCluster(run: run)
        
        return CanvasAsset(
            type: .stats,
            content: .stats(stats),
            position: position,
            fontSize: 12,
            fontWeight: .medium,
            color: .white,
            editableType: .none,
            canDelete: false // Core element
        )
    }
    
    // MARK: - Generate Default Layout for RunActivity
    
    static func generateDefaultAssets(for run: RunActivity, canvasSize: CGSize) -> [CanvasAsset] {
        print("🎨 Creating edge-based canvas layout for run: \(run.name)")
        print("🎨 Canvas size: \(canvasSize)")
        
        var assets: [CanvasAsset] = []
        
        // Edge-based alignment using SwiftUI alignments
        
        // 1. TITLE & DISTANCE (center alignment)
        var titleAsset = createTitleDistance(for: run, position: .zero)
        titleAsset.alignment = .center
        titleAsset.fontSize = 28 // Large, prominent title
        titleAsset.fontWeight = .bold
        assets.append(titleAsset)
        print("  ✅ Added title/distance with center alignment")
        
        // 2. STATS CLUSTER (top-trailing edge)
        var statsAsset = createStatsCluster(for: run, position: .zero)
        statsAsset.alignment = .topTrailing
        assets.append(statsAsset)
        print("  ✅ Added stats cluster with topTrailing alignment")
        
        // 3. LOCATION (top-trailing edge, below stats)
        if var locationAsset = createLocation(for: run, position: .zero) {
            locationAsset.alignment = .topTrailing
            assets.append(locationAsset)
            print("  ✅ Added location with topTrailing alignment")
        }
        
        // 4. ROUTE MAP (center, middle portion)
        if !run.routeCoordinates.isEmpty {
            var routeAsset = createRoute(for: run, position: .zero)
            routeAsset.alignment = .center
            routeAsset.scale = 1.2 // Larger map
            assets.append(routeAsset)
            print("  ✅ Added route map with center alignment")
        }
        
        // 5. SONG LIST (leading edge)
        if let tracks = run.spotifyTracks, !tracks.isEmpty {
            var songListAsset = createSongList(for: run, position: .zero)
            songListAsset.alignment = .leading
            assets.append(songListAsset)
            print("  ✅ Added song list with leading alignment")
        }
        
        // 6. ALBUM ART (multiple albums, positioned on trailing edge)
        var qualifyingAlbums: [(String, [SpotifyTrack])] = []
        if let tracks = run.spotifyTracks, !tracks.isEmpty {
            // Group tracks by album
            let albumGroups = Dictionary(grouping: tracks) { track in
                "\(track.album ?? "Unknown")|\(track.artist)" // Use string key instead of tuple
            }
            
            // Find albums with 3+ tracks and sort by track count (most tracks first)
            qualifyingAlbums = albumGroups.filter { $0.value.count >= 3 }.sorted { $0.value.count > $1.value.count }
            
            if !qualifyingAlbums.isEmpty {
                print("  🎨 Found \(qualifyingAlbums.count) albums with 3+ tracks:")
                for (albumKey, albumTracks) in qualifyingAlbums {
                    let parts = albumKey.split(separator: "|")
                    let albumName = String(parts.first ?? "Unknown")
                    print("    - \(albumName): \(albumTracks.count) tracks")
                }
                
                // Position up to 3 album arts vertically on the right side
                let maxAlbums = min(3, qualifyingAlbums.count)
                for (index, (albumKey, albumTracks)) in qualifyingAlbums.prefix(maxAlbums).enumerated() {
                    let parts = albumKey.split(separator: "|")
                    let albumName = String(parts.first ?? "Unknown")
                    let artistName = String(parts.last ?? "Unknown")
                    
                    // Use album art from any track in this album
                    if let albumImageURL = albumTracks.first?.albumImageURL {
                        // Position albums vertically with spacing
                        let baseY = 0.65 // Start at 65% down
                        let spacing = 0.12 // 12% spacing between albums
                        let yPosition = baseY + (Double(index) * spacing)
                        
                        var albumArtAsset = createAlbumArt(
                            imageURL: albumImageURL,
                            imageData: nil,
                            albumName: albumName,
                            artistName: artistName,
                            position: .zero, // Not used when anchorPoint is set
                            anchorPoint: CGPoint(x: 0.88, y: yPosition) // 88% right, spaced vertically
                        )
                        albumArtAsset.scale = 0.7 // Smaller for multiple albums
                        albumArtAsset.zIndex = 5.0 + Double(index) * 0.1 // Ensure layering
                        assets.append(albumArtAsset)
                        print("  ✅ Added album art #\(index + 1) - \(albumName) (\(albumTracks.count) tracks)")
                        print("    🎨 Position: (0.88, \(yPosition)), scale: \(albumArtAsset.scale)")
                    }
                }
            } else {
                print("  ℹ️ No albums with 3+ tracks found for album art")
            }
        }
        
        // 7. POWER SONG (positioned below all album arts with no overlap)
        if var powerSongAsset = createPowerSong(for: run, position: .zero) {
            powerSongAsset.alignment = nil // Use percentage positioning
            
            // Calculate position below the last album art
            let albumCount = qualifyingAlbums.count
            let maxDisplayedAlbums = min(3, albumCount)
            let baseY = 0.65 // Album art starts at 65%
            let spacing = 0.12 // 12% spacing between albums
            let lastAlbumY = baseY + (Double(maxDisplayedAlbums - 1) * spacing)
            let powerSongY = min(0.94, lastAlbumY + 0.15) // Position below last album art, max 94%
            
            powerSongAsset.anchorPoint = CGPoint(x: 0.75, y: powerSongY) // Further left, below all album arts
            powerSongAsset.fontSize = 10 // Smaller font
            powerSongAsset.scale = 0.8 // Smaller overall
            assets.append(powerSongAsset)
            print("  ✅ Added power song at (0.75, \(powerSongY)) - below \(maxDisplayedAlbums) album art(s)")
        }
        
        print("🎨 Generated \(assets.count) canvas assets with edge-based alignment")
        return assets
    }
}