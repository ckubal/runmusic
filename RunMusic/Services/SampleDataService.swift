import Foundation
import CoreLocation

/// Service to provide sample data for non-authenticated users
class SampleDataService {
    static let shared = SampleDataService()
    
    private init() {}
    
    /// Create sample runs with realistic data for preview
    func createSampleRuns() -> [RunActivity] {
        let sampleRuns = [
            createSampleRun1(),
            createSampleRun2()
        ]
        
        return sampleRuns
    }
    
    // MARK: - Sample Run 1: Golden Gate Park Morning Run
    
    private func createSampleRun1() -> RunActivity {
        let runDate = Date().addingTimeInterval(-86400 * 2) // 2 days ago
        let distance: Double = 5000 // 5km in meters
        let elapsedTime: TimeInterval = 1800 // 30 minutes
        
        // Golden Gate Park route coordinates
        let routeCoordinates = [
            LocationData(latitude: 37.7694, longitude: -122.4862, timestamp: runDate),
            LocationData(latitude: 37.7704, longitude: -122.4852, timestamp: runDate.addingTimeInterval(180)),
            LocationData(latitude: 37.7714, longitude: -122.4842, timestamp: runDate.addingTimeInterval(360)),
            LocationData(latitude: 37.7724, longitude: -122.4832, timestamp: runDate.addingTimeInterval(540)),
            LocationData(latitude: 37.7734, longitude: -122.4822, timestamp: runDate.addingTimeInterval(720)),
            LocationData(latitude: 37.7744, longitude: -122.4812, timestamp: runDate.addingTimeInterval(900)),
            LocationData(latitude: 37.7754, longitude: -122.4802, timestamp: runDate.addingTimeInterval(1080)),
            LocationData(latitude: 37.7764, longitude: -122.4792, timestamp: runDate.addingTimeInterval(1260)),
            LocationData(latitude: 37.7774, longitude: -122.4782, timestamp: runDate.addingTimeInterval(1440)),
            LocationData(latitude: 37.7784, longitude: -122.4772, timestamp: runDate.addingTimeInterval(1620)),
            LocationData(latitude: 37.7794, longitude: -122.4762, timestamp: runDate.addingTimeInterval(1800))
        ]
        
        // Sample Spotify tracks with realistic timing
        let sampleTracks = [
            SpotifyTrack(
                id: "sample_1_1",
                name: "Blinding Lights",
                artist: "The Weeknd",
                album: "After Hours",
                playedAt: runDate.addingTimeInterval(30),
                durationMs: 200040,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273c02d5c4b9777058ef4b0346e",
                isFavorite: true,
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_1_2",
                name: "Levitating",
                artist: "Dua Lipa",
                album: "Future Nostalgia",
                playedAt: runDate.addingTimeInterval(270),
                durationMs: 203064,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273179204c70d0a5b4b7c8c4d9e",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_1_3",
                name: "Good 4 U",
                artist: "Olivia Rodrigo",
                album: "SOUR",
                playedAt: runDate.addingTimeInterval(510),
                durationMs: 178147,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273a91c10fe9472d9bd89802e5a",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_1_4",
                name: "Heat Waves",
                artist: "Glass Animals",
                album: "Dreamland",
                playedAt: runDate.addingTimeInterval(720),
                durationMs: 238805,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273c0a72d5c0c567a096c1e0b86",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_1_5",
                name: "Stay",
                artist: "The Kid LAROI, Justin Bieber",
                album: "F*CK LOVE 3: OVER YOU",
                playedAt: runDate.addingTimeInterval(960),
                durationMs: 141806,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273fc915b69600616c2f8b75abb",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_1_6",
                name: "Industry Baby",
                artist: "Lil Nas X, Jack Harlow",
                album: "MONTERO",
                playedAt: runDate.addingTimeInterval(1140),
                durationMs: 212517,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273c7b6b51cc6aa794ac3b9a8a3",
                isVisible: true
            )
        ]
        
        var sampleRun = RunActivity(
            id: "sample_run_1",
            name: "Sample: Golden Gate Park Morning",
            date: runDate,
            distance: distance,
            elapsedTime: elapsedTime,
            averagePace: elapsedTime / (distance / 1000), // seconds per km
            startLocation: routeCoordinates.first!,
            endLocation: routeCoordinates.last!,
            routeCoordinates: routeCoordinates,
            city: "San Francisco",
            neighborhood: "Golden Gate Park",
            spotifyTracks: sampleTracks
        )
        
        // Set up smart location analysis for neighborhood display
        sampleRun.locationAnalysis = RunLocationAnalysis(
            type: .neighborhoodInCity,
            displayText: "Golden Gate Park in San Francisco",
            primaryCity: "San Francisco",
            secondaryCity: nil,
            neighborhood: "Golden Gate Park"
        )
        
        // Set up portrait settings with sample customizations
        sampleRun.portraitSettings.showCity = true
        sampleRun.portraitSettings.showSongs = true
        sampleRun.portraitSettings.colorScheme = RunColorScheme.presets[2] // Use a nice gradient
        sampleRun.portraitSettings.fontFamily = FontFamily.presets[0] // Helvetica Neue
        
        return sampleRun
    }
    
    // MARK: - Sample Run 2: Central Park Evening Run
    
    private func createSampleRun2() -> RunActivity {
        let runDate = Date().addingTimeInterval(-86400 * 5) // 5 days ago
        let distance: Double = 6400 // 6.4km in meters  
        let elapsedTime: TimeInterval = 2100 // 35 minutes
        
        // Central Park route coordinates (NYC)
        let routeCoordinates = [
            LocationData(latitude: 40.7829, longitude: -73.9654, timestamp: runDate),
            LocationData(latitude: 40.7839, longitude: -73.9644, timestamp: runDate.addingTimeInterval(210)),
            LocationData(latitude: 40.7849, longitude: -73.9634, timestamp: runDate.addingTimeInterval(420)),
            LocationData(latitude: 40.7859, longitude: -73.9624, timestamp: runDate.addingTimeInterval(630)),
            LocationData(latitude: 40.7869, longitude: -73.9614, timestamp: runDate.addingTimeInterval(840)),
            LocationData(latitude: 40.7879, longitude: -73.9604, timestamp: runDate.addingTimeInterval(1050)),
            LocationData(latitude: 40.7889, longitude: -73.9594, timestamp: runDate.addingTimeInterval(1260)),
            LocationData(latitude: 40.7899, longitude: -73.9584, timestamp: runDate.addingTimeInterval(1470)),
            LocationData(latitude: 40.7909, longitude: -73.9574, timestamp: runDate.addingTimeInterval(1680)),
            LocationData(latitude: 40.7919, longitude: -73.9564, timestamp: runDate.addingTimeInterval(1890)),
            LocationData(latitude: 40.7929, longitude: -73.9554, timestamp: runDate.addingTimeInterval(2100))
        ]
        
        // Sample Spotify tracks for the second run
        let sampleTracks = [
            SpotifyTrack(
                id: "sample_2_1",
                name: "As It Was",
                artist: "Harry Styles",
                album: "Harry's House",
                playedAt: runDate.addingTimeInterval(45),
                durationMs: 167303,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b2732e8ed79e177ff6011076f5f0",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_2_2", 
                name: "First Class",
                artist: "Jack Harlow",
                album: "Come Home The Kids Miss You",
                playedAt: runDate.addingTimeInterval(230),
                durationMs: 169000,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273d929bb24b9f8d15e4c6e6bab",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_2_3",
                name: "Anti-Hero",
                artist: "Taylor Swift",
                album: "Midnights",
                playedAt: runDate.addingTimeInterval(420),
                durationMs: 200690,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273bb54dde68cd23e2a268ae0f5",
                isFavorite: true,
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_2_4",
                name: "Unholy",
                artist: "Sam Smith, Kim Petras",
                album: "Gloria",
                playedAt: runDate.addingTimeInterval(640),
                durationMs: 156481,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b27382cf2c59bb4bba9aec0c6ef6",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_2_5",
                name: "Bad Habit",
                artist: "Steve Lacy",
                album: "Gemini Rights",
                playedAt: runDate.addingTimeInterval(820),
                durationMs: 223000,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273b85c45eee1bb46872c0285a5",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_2_6",
                name: "Running Up That Hill",
                artist: "Kate Bush",
                album: "Hounds of Love",
                playedAt: runDate.addingTimeInterval(1060),
                durationMs: 300000,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b273b0da32f3d43ddeacfccad8e1",
                isVisible: true
            ),
            SpotifyTrack(
                id: "sample_2_7",
                name: "Something in the Orange",
                artist: "Zach Bryan",
                album: "American Heartbreak",
                playedAt: runDate.addingTimeInterval(1380),
                durationMs: 216000,
                albumImageURL: "https://i.scdn.co/image/ab67616d0000b2736968f8b2c5b55256bbafb905",
                isVisible: true
            )
        ]
        
        var sampleRun = RunActivity(
            id: "sample_run_2",
            name: "Sample: Central Park Evening",
            date: runDate,
            distance: distance,
            elapsedTime: elapsedTime,
            averagePace: elapsedTime / (distance / 1000), // seconds per km
            startLocation: routeCoordinates.first!,
            endLocation: routeCoordinates.last!,
            routeCoordinates: routeCoordinates,
            city: "New York",
            neighborhood: "Central Park",
            spotifyTracks: sampleTracks
        )
        
        // Set up smart location analysis for neighborhood display
        sampleRun.locationAnalysis = RunLocationAnalysis(
            type: .neighborhoodInCity,
            displayText: "Central Park in New York",
            primaryCity: "New York",
            secondaryCity: nil,
            neighborhood: "Central Park"
        )
        
        // Set up different settings to show variety
        sampleRun.portraitSettings.showCity = true
        sampleRun.portraitSettings.showSongs = true
        sampleRun.portraitSettings.colorScheme = RunColorScheme.presets[5] // Different color scheme
        sampleRun.portraitSettings.fontFamily = FontFamily.presets[1] // San Francisco
        
        return sampleRun
    }
}