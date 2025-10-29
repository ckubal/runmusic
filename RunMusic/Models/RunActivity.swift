import Foundation
import CoreLocation

// MARK: - Weather Data Models

struct WeatherData: Codable {
    let temperature: Double // in Fahrenheit
    let condition: WeatherCondition
    let windSpeed: Double? // mph
    let humidity: Double? // percentage
    let timeOfDay: TimeOfDay
    let description: String? // e.g., "Clear sky", "Light rain"
    let dataSource: DataSource? // for debugging - can be removed later
    
    enum WeatherCondition: String, Codable {
        case clear = "clear"
        case cloudy = "cloudy"
        case rain = "rain"
        case snow = "snow"
        case fog = "fog"
        case thunderstorm = "thunderstorm"
        case unknown = "unknown"
    }
    
    enum TimeOfDay: String, Codable {
        case dawn = "dawn"
        case morning = "morning"
        case afternoon = "afternoon"
        case evening = "evening"
        case night = "night"
    }
    
    enum DataSource: String, Codable {
        case api = "api"
        case simulated = "simulated"
    }
}

// Simplified to only support portrait mode (9:16 format)
enum ShareableCardLayoutType: String, CaseIterable, Codable {
    case portrait = "portrait"   // 9:16 vertical portrait
    
    var displayName: String {
        return "portrait"
    }
    
    var aspectRatio: CGFloat {
        return 9.0/16.0   // 0.5625
    }
    
    var dimensions: CGSize {
        return CGSize(width: 1080, height: 1920)  // Portrait format
    }
}

// MARK: - Photo Assignment Caching

struct PhotoAssignmentMetadata: Codable {
    let searchDate: Date // When the photo search was performed
    let assignmentType: PhotoAssignmentType // How the photo was assigned
    let searchResults: PhotoSearchResults // What was found during search
    
    enum PhotoAssignmentType: String, Codable {
        case runTimeframe = "run_timeframe" // Photo found during run time
        case sameDayExpanded = "same_day_expanded" // Photo found on same day (expanded search)
        case recentCameraRoll = "recent_camera_roll" // Fallback to recent photos
        case defaultGradient = "default_gradient" // No photos found, using gradient
        case userSelected = "user_selected" // User manually selected a photo
    }
    
    struct PhotoSearchResults: Codable {
        let runTimeframePhotos: Int // Number of photos found during run
        let sameDayPhotos: Int // Number of photos found on same day
        let recentPhotos: Int // Number of recent photos available
        let hasPhotoLibraryAccess: Bool // Whether photo access was granted
        let searchTimeMs: Double // How long the search took
    }
    
    // Check if cached assignment is still valid (within 7 days)
    var isValid: Bool {
        let maxAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days
        return Date().timeIntervalSince(searchDate) < maxAge
    }
    
    // Check if we should prefer this cached result over searching again
    var shouldUseCachedResult: Bool {
        switch assignmentType {
        case .runTimeframe, .userSelected:
            return isValid // Always prefer run-time photos and user selections if valid
        case .sameDayExpanded:
            return isValid && searchResults.runTimeframePhotos == 0 // Only if no run-time photos were found
        case .recentCameraRoll, .defaultGradient:
            return isValid && searchResults.sameDayPhotos == 0 // Only if no better photos were found
        }
    }
}

struct LayoutSpecificSettings: Codable {
    // Shared settings (persist between layouts)
    var showCity: Bool? // nil = use default
    var showSongs: Bool? // nil = use default
    var showDate: Bool? // nil = use default
    var showTime: Bool? // nil = use default
    var showPace: Bool? // nil = use default
    var showTemperature: Bool? // nil = use default
    var backgroundPhoto: RunPhotoBackground? // nil = no photo background
    var colorScheme: RunColorScheme? // nil = use default
    var fontFamily: FontFamily? // nil = use default
    var albumArtDisplays: [AlbumArtDisplay]? // nil = no album art (visibility only, not positions)
    var powerSongDisplay: PowerSongDisplay? // nil = no power song display
    
    // Photo assignment caching
    var photoAssignmentMetadata: PhotoAssignmentMetadata? // Cache photo search results
    
    // Layout-specific settings (independent per layout)
    var hasUnsavedChanges: Bool = false
    var lastModified: Date?
    
    // Transform settings are handled separately in the interactive views
    // This allows positioning to remain layout-specific while content stays shared
}

struct RunActivity: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    let date: Date
    let distance: Double // in meters
    let elapsedTime: TimeInterval // in seconds
    let averagePace: Double // in seconds per kilometer
    let startLocation: LocationData?
    let endLocation: LocationData?
    let routeCoordinates: [LocationData]
    var city: String?
    let neighborhood: String?
    var locationAnalysis: RunLocationAnalysis?
    var spotifyTracks: [SpotifyTrack]?
    
    // Power Song Analysis - track with fastest average pace during its play duration
    var powerSong: SpotifyTrack?
    var powerSongAveragePace: Double? // seconds per kilometer during the power song
    
    // Weather Data - conditions during the run for context and route color mapping
    var weatherData: WeatherData?
    
    // Computed property for smart location display
    var smartLocationDisplay: String? {
        return locationAnalysis?.displayText ?? city
    }
    
    // Weather-based route color selection
    var weatherBasedRouteColor: RunColorScheme? {
        guard let weather = weatherData else { return nil }
        
        // Temperature-based colors
        switch weather.temperature {
        case 80...: // Hot day (80°F+)
            return RunColorScheme.presets.first { $0.name == "sunset" } ?? RunColorScheme.presets[0]
        case ..<40: // Cold day (below 40°F)
            return RunColorScheme.presets.first { $0.name == "arctic" } ?? RunColorScheme.presets[1]
        default:
            break
        }
        
        // Condition-based colors
        switch weather.condition {
        case .rain, .thunderstorm:
            return RunColorScheme.presets.first { $0.name == "storm" } ?? RunColorScheme.presets[2]
        case .snow:
            return RunColorScheme.presets.first { $0.name == "arctic" } ?? RunColorScheme.presets[1]
        case .clear where weather.timeOfDay == .night:
            return RunColorScheme.presets.first { $0.name == "midnight" } ?? RunColorScheme.presets[3]
        case .clear where weather.timeOfDay == .morning || weather.timeOfDay == .dawn:
            return RunColorScheme.presets.first { $0.name == "dawn" } ?? RunColorScheme.presets[4]
        case .fog, .cloudy:
            return RunColorScheme.presets.first { $0.name == "mist" } ?? RunColorScheme.presets[5]
        default:
            // Pleasant weather - use nature/green theme
            return RunColorScheme.presets.first { $0.name == "nature" } ?? RunColorScheme.presets[6]
        }
    }
    
    // Portrait-only customization settings (simplified from layout-specific)
    var portraitSettings: LayoutSpecificSettings = LayoutSpecificSettings()
    
    // Legacy properties for backward compatibility - map to portrait settings
    var showCity: Bool? {
        get { portraitSettings.showCity }
        set { portraitSettings.showCity = newValue }
    }
    var showSongs: Bool? {
        get { portraitSettings.showSongs }
        set { portraitSettings.showSongs = newValue }
    }
    var backgroundPhoto: RunPhotoBackground? {
        get { portraitSettings.backgroundPhoto }
        set { portraitSettings.backgroundPhoto = newValue }
    }
    var colorScheme: RunColorScheme? {
        get { portraitSettings.colorScheme }
        set { portraitSettings.colorScheme = newValue }
    }
    var fontFamily: FontFamily? {
        get { portraitSettings.fontFamily }
        set { portraitSettings.fontFamily = newValue }
    }
    var albumArtDisplays: [AlbumArtDisplay]? {
        get { portraitSettings.albumArtDisplays }
        set { portraitSettings.albumArtDisplays = newValue }
    }
    
    var distanceInKilometers: Double {
        distance / 1000.0
    }
    
    // MARK: - Smart Layout Management
    
    /// Copy shared settings from source layout to target layout
    mutating func syncSharedSettings(from sourceLayout: ShareableCardLayoutType, to targetLayout: ShareableCardLayoutType) {
        let sourceSettings = getSettings(for: sourceLayout)
        var targetSettings = getSettings(for: targetLayout)
        
        // Copy shared settings
        targetSettings.showCity = sourceSettings.showCity
        targetSettings.showSongs = sourceSettings.showSongs
        targetSettings.backgroundPhoto = sourceSettings.backgroundPhoto
        targetSettings.colorScheme = sourceSettings.colorScheme
        
        // Copy album art visibility (but reset positions to layout-appropriate defaults)
        if let sourceAlbumArt = sourceSettings.albumArtDisplays {
            var newAlbumArt = sourceAlbumArt
            // Reset positions to default portrait positioning
            for i in 0..<newAlbumArt.count {
                let row = i / 2
                let col = i % 2
                
                // Use consistent portrait positioning (bottom-right area)
                newAlbumArt[i].offsetX = CGFloat(80 + (col * 50))
                newAlbumArt[i].offsetY = CGFloat(120 + (row * 50))
                newAlbumArt[i].scale = 0.8 // 80% size as requested
                newAlbumArt[i].rotationDegrees = 0
            }
            targetSettings.albumArtDisplays = newAlbumArt
        }
        
        setSettings(targetSettings, for: targetLayout)
    }
    
    /// Check if a layout has unsaved changes
    func hasUnsavedChanges(for layout: ShareableCardLayoutType) -> Bool {
        return getSettings(for: layout).hasUnsavedChanges
    }
    
    /// Mark a layout as having changes
    mutating func markAsChanged(layout: ShareableCardLayoutType) {
        var settings = getSettings(for: layout)
        settings.hasUnsavedChanges = true
        settings.lastModified = Date()
        setSettings(settings, for: layout)
    }
    
    /// Mark a layout as saved
    mutating func markAsSaved(layout: ShareableCardLayoutType) {
        var settings = getSettings(for: layout)
        settings.hasUnsavedChanges = false
        setSettings(settings, for: layout)
    }
    
    // Simplified helper functions (portrait only)
    private func getSettings(for layout: ShareableCardLayoutType) -> LayoutSpecificSettings {
        return portraitSettings // Always portrait now
    }
    
    private mutating func setSettings(_ settings: LayoutSpecificSettings, for layout: ShareableCardLayoutType) {
        portraitSettings = settings // Always portrait now
    }
    
    var distanceInMiles: Double {
        distance / 1609.34
    }
    
    var pacePerMile: String {
        let paceInSecondsPerMile = averagePace * 1.60934
        let minutes = Int(paceInSecondsPerMile / 60)
        let seconds = Int(paceInSecondsPerMile.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var pacePerKm: String {
        let minutes = Int(averagePace / 60)
        let seconds = Int(averagePace.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedDuration: String {
        let hours = Int(elapsedTime / 3600)
        let minutes = Int((elapsedTime.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(elapsedTime.truncatingRemainder(dividingBy: 60))
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var compactFormattedDuration: String {
        let hours = Int(elapsedTime / 3600)
        let minutes = Int((elapsedTime.truncatingRemainder(dividingBy: 3600)) / 60)
        
        if hours > 0 {
            return String(format: "%d:%02d", hours, minutes) // e.g. "1:21"
        } else {
            return String(format: "%dm", minutes) // e.g. "41m"
        }
    }
    
    var powerSongPacePerKm: String? {
        guard let pace = powerSongAveragePace else { return nil }
        let minutes = Int(pace / 60)
        let seconds = Int(pace.truncatingRemainder(dividingBy: 60))
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var powerSongPacePerMile: String? {
        guard let pace = powerSongAveragePace else { return nil }
        // pace is stored as seconds per km, convert to minutes per mile
        let paceSecondsPerKm = pace
        let paceSecondsPerMile = paceSecondsPerKm * 1.60934  // km to mile conversion
        let minutesPerMile = paceSecondsPerMile / 60.0
        let minutes = Int(minutesPerMile)
        let seconds = Int((minutesPerMile - Double(minutes)) * 60)
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Equatable & Hashable Conformance
    
    static func == (lhs: RunActivity, rhs: RunActivity) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct LocationData: Codable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date?
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct SpotifyTrack: Identifiable, Codable {
    let id: String
    let name: String
    let artist: String
    let album: String?
    let playedAt: Date
    let durationMs: Int
    let albumImageURL: String? // Album art URL from Spotify
    var isFavorite: Bool = false
    var isVisible: Bool = true
    
    // Custom initializer for album art enrichment
    init(id: String, name: String, artist: String, album: String?, playedAt: Date, durationMs: Int, albumImageURL: String?, isFavorite: Bool = false, isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.playedAt = playedAt
        self.durationMs = durationMs
        self.albumImageURL = albumImageURL
        self.isFavorite = isFavorite
        self.isVisible = isVisible
    }
    
    var formattedDuration: String {
        let totalSeconds = durationMs / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Photo Background Models

struct RunPhotoBackground: Codable {
    let photoId: String // Unique identifier for the photo
    let photoData: Data? // Actual image data (stored locally)
    let filterType: PhotoFilterType
    let opacity: Double // 0.0 to 1.0 for background opacity
    
    enum PhotoFilterType: String, CaseIterable, Codable {
        case blur = "blur"
        case vintage = "vintage"
        case sepia = "sepia"
        case blackAndWhite = "black_and_white"
        case highContrast = "high_contrast"
        case cinematic = "cinematic"
        case softFocus = "soft_focus"
        
        var displayName: String {
            switch self {
            case .blur: return "blur"
            case .vintage: return "vintage"
            case .sepia: return "sepia"
            case .blackAndWhite: return "b&w"
            case .highContrast: return "contrast"
            case .cinematic: return "cinematic"
            case .softFocus: return "soft focus"
            }
        }
    }
}

// MARK: - Location Analysis Data Models

struct RunLocationAnalysis: Codable {
    let type: RunLocationType
    let displayText: String
    let primaryCity: String?
    let secondaryCity: String?
    let neighborhood: String?
    
    // Note: rawLocationData is not stored (too complex for Codable, used only during analysis)
}

enum RunLocationType: String, Codable, CaseIterable {
    case singleLocation      // "San Francisco"
    case neighborhoodInCity  // "Mission District in San Francisco"
    case multiCity          // "San Francisco → Oakland"
    case complexRoute       // "Multi-city run"
}

struct DetailedLocationInfo {
    let pointType: LocationPointType
    let neighborhood: String?
    let city: String?
    let subAdministrativeArea: String?
    let administrativeArea: String?
    let country: String?
    let coordinate: CLLocationCoordinate2D
    
    var bestCityName: String? {
        return city ?? subAdministrativeArea ?? administrativeArea
    }
    
    var debugDescription: String {
        let neighborhoodText = neighborhood ?? "nil"
        let cityText = bestCityName ?? "nil"
        return "\(neighborhoodText) in \(cityText)"
    }
}

enum LocationPointType: CustomStringConvertible {
    case start
    case furthest
    case intermediate
    case end
    
    var description: String {
        switch self {
        case .start: return "START"
        case .furthest: return "FURTHEST"
        case .intermediate: return "MID"
        case .end: return "END"
        }
    }
}