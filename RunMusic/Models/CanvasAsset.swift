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

// MARK: - Canvas Asset for Run Details Canvas View

struct CanvasAsset: Identifiable, Equatable, Codable {
    let id = UUID()
    var type: AssetType
    var content: AssetContent
    var position: CGPoint
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
        case type, content, position, rotation, scale, fontSize, fontWeight, fontFamily, color, showBlackOutline
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
            formatter.dateFormat = "MMM d"
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
        formatter.dateFormat = "MMM d"
        self.date = formatter.string(from: run.date).lowercased()
        
        self.time = run.formattedDuration
        
        if let weather = run.weatherData {
            self.weather = "\(Int(weather.temperature))°F"
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
        
        return CanvasAsset(
            type: .songList,
            content: .songList(tracks: tracks, powerSongId: powerSongId),
            position: position,
            fontSize: 12,
            fontWeight: .medium,
            editableType: .list,
            canDelete: tracks.isEmpty // Can delete if no songs
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
        guard let powerSong = run.powerSong else { return nil }
        
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
    
    static func createAlbumArt(imageURL: String?, imageData: Data?, albumName: String, artistName: String, position: CGPoint) -> CanvasAsset {
        return CanvasAsset(
            type: .albumArt,
            content: .albumArt(imageURL: imageURL, imageData: imageData, albumName: albumName, artistName: artistName),
            position: position,
            scale: 0.6,
            zIndex: 1.5,
            editableType: .visual
        )
    }
    
    static func createLocation(for run: RunActivity, position: CGPoint = CGPoint(x: 200, y: 150)) -> CanvasAsset? {
        guard let location = run.smartLocationDisplay else { return nil }
        
        return CanvasAsset(
            type: .location,
            content: .location(location),
            position: position,
            fontSize: 14,
            fontWeight: .medium,
            color: .cyan,
            editableType: .text
        )
    }
    
    // MARK: - Generate Default Layout for RunActivity
    
    static func generateDefaultAssets(for run: RunActivity, canvasSize: CGSize) -> [CanvasAsset] {
        var assets: [CanvasAsset] = []
        
        let centerX = canvasSize.width / 2
        let topY = canvasSize.height * 0.15
        let middleY = canvasSize.height * 0.4
        let bottomY = canvasSize.height * 0.75
        
        // Core assets (always present)
        assets.append(createTitleDistance(for: run, position: CGPoint(x: centerX, y: topY)))
        
        if !run.routeCoordinates.isEmpty {
            assets.append(createRoute(for: run, position: CGPoint(x: centerX, y: middleY)))
        }
        
        // Stats in top-right area
        let statsStartX = canvasSize.width * 0.7
        let statsY = topY * 0.5
        
        assets.append(createPace(for: run, position: CGPoint(x: statsStartX, y: statsY)))
        assets.append(createDate(for: run, position: CGPoint(x: statsStartX, y: statsY + 25)))
        assets.append(createTime(for: run, position: CGPoint(x: statsStartX, y: statsY + 50)))
        
        if let weatherAsset = createWeather(for: run, position: CGPoint(x: statsStartX, y: statsY + 75)) {
            assets.append(weatherAsset)
        }
        
        // Optional assets
        if let location = createLocation(for: run, position: CGPoint(x: centerX, y: topY + 60)) {
            assets.append(location)
        }
        
        if let powerSong = createPowerSong(for: run, position: CGPoint(x: canvasSize.width * 0.95, y: bottomY)) {
            assets.append(powerSong)
        }
        
        // Song list in bottom-left
        if let tracks = run.spotifyTracks, !tracks.isEmpty {
            assets.append(createSongList(for: run, position: CGPoint(x: canvasSize.width * 0.05, y: bottomY - 50)))
        }
        
        // Album art scattered around
        if let firstTrack = run.spotifyTracks?.first,
           let albumArt = run.portraitSettings.albumArtDisplays?.first {
            let albumAsset = createAlbumArt(
                imageURL: firstTrack.albumImageURL,
                imageData: nil, // Will be loaded asynchronously
                albumName: firstTrack.album ?? "Unknown Album",
                artistName: firstTrack.artist,
                position: CGPoint(x: albumArt.offsetX, y: albumArt.offsetY)
            )
            assets.append(albumAsset)
        }
        
        return assets
    }
}