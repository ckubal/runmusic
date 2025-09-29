import SwiftUI
import CoreLocation

struct RunCardView: View {
    let run: RunActivity
    
    var body: some View {
        ZStack {
            // Background layer - photo background with fallback gradient
            Group {
                if let photoBackground = run.backgroundPhoto,
                   photoBackground.photoData != nil {
                    PhotoBackgroundView(photoBackground: photoBackground)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    fallbackGradientForRun(run)
                }
            }
            
            // Route line as background element - positioned on right side
            HStack {
                Spacer()
                RoutePathView(
                    coordinates: run.routeCoordinates,
                    lineWidth: 4.0,
                    colorScheme: run.weatherBasedRouteColor ?? run.colorScheme ?? RunColorScheme.presets[0]
                )
                .opacity(0.6)
                .frame(width: 120, height: 120)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Dark overlay for better text readability
            Color.black
            
            // Content overlay
            VStack(spacing: 0) {
                // Top section - Run title and indicators
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(run.name.lowercased())
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 1, y: 1)
                            .lineLimit(2)
                        
                        // Location display
                        if let locationText = run.smartLocationDisplay {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.8))
                                Text(locationText.lowercased())
                                    .font(.custom("Helvetica Neue", size: 13))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .shadow(color: .black.opacity(0.6), radius: 1)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        // Date
                        Text(formatDateForDisplay(run.date))
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.6), radius: 1)
                        
                        // Music indicator with song count
                        if let tracks = run.spotifyTracks, !tracks.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 14))
                                    .foregroundColor(.green)
                                    .shadow(color: .black.opacity(0.6), radius: 1)
                                
                                Text("\(tracks.count)")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
                                    .shadow(color: .black.opacity(0.6), radius: 1)
                            }
                        }
                        
                        // Weather indicator
                        if let weather = run.weatherData {
                            HStack(spacing: 4) {
                                Text(weather.condition.emoji)
                                    .font(.system(size: 12))
                                
                                Text("\(Int(weather.temperature))°F")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .fontWeight(.medium)
                                    .foregroundColor(.white.opacity(0.9))
                                    .shadow(color: .black.opacity(0.6), radius: 1)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Bottom section - Prominent distance + other stats
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        // DISTANCE - Front and center with prominent display
                        HStack(spacing: 4) {
                            Text(formatDistance(run.distance))
                                .font(.custom("Helvetica Neue", size: 18))
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text(distanceUnitAbbreviation())
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.orange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                        )
                        .cornerRadius(16)
                        
                        // Other stats in smaller pills
                        HStack(spacing: 6) {
                            RunStatBadge(
                                icon: "speedometer",
                                value: UserPreferences.shared.formatPace(run.averagePace),
                                unit: "/\(UserPreferences.shared.distanceUnit == .miles ? "mi" : "km")",
                                color: .green
                            )
                            
                            RunStatBadge(
                                icon: "clock",
                                value: run.compactFormattedDuration,
                                unit: "",
                                color: .blue
                            )
                        }
                    }
                    
                    Spacer()
                    
                    // Power song display - bottom-aligned
                    if let powerSong = run.powerSong {
                        VStack(alignment: .trailing, spacing: 0) {
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                // Power song name with fire emoji
                                HStack(spacing: 4) {
                                    Text("🔥")
                                        .font(.system(size: 14))
                                    Text(powerSong.name.lowercased())
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                                
                                // Artist name
                                Text(powerSong.artist.lowercased())
                                    .font(.custom("Helvetica Neue", size: 10))
                                    .foregroundColor(.white.opacity(0.6))
                                    .lineLimit(1)
                                
                                // Power song pace
                                if let powerSongPace = run.powerSongPacePerMile {
                                    Text(powerSongPace + "/mi")
                                        .font(.custom("Helvetica Neue", size: 10))
                                        .foregroundColor(.orange)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.4))
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.3), radius: 2)
                        }
                    }
                }
            }
            .padding(18)
        }
        .frame(height: 200) // Taller to match original RunTunes dimensions
        .contentShape(Rectangle())
        .cornerRadius(20) // More rounded for modern look
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Helper Functions
    
    private func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }
    
    private func formatDistance(_ meters: Double) -> String {
        let userPrefs = UserPreferences.shared
        switch userPrefs.distanceUnit {
        case .miles:
            let miles = meters / 1609.34
            return String(format: "%.2f", miles)
        case .kilometers:
            let km = meters / 1000.0
            return String(format: "%.2f", km)
        }
    }
    
    private func distanceUnitAbbreviation() -> String {
        return UserPreferences.shared.distanceUnit.abbreviation.lowercased()
    }
    
    private func fallbackGradientForRun(_ run: RunActivity) -> LinearGradient {
        // More diverse gradient backgrounds based on run characteristics
        let gradientVariations: [[Color]] = [
            // Morning runs - warm sunrise
            [Color.orange, Color.pink.opacity(0.8), Color.red.opacity(0.6)],
            // Evening runs - cool blue
            [Color.blue, Color.cyan.opacity(0.8), Color.teal.opacity(0.6)],
            // Night runs - purple vibes
            [Color.purple, Color.pink.opacity(0.8), Color.indigo.opacity(0.6)],
            // Nature runs - green
            [Color.green, Color.mint.opacity(0.8), Color.teal.opacity(0.6)],
            // Fast runs - energy orange
            [Color.orange, Color.yellow.opacity(0.8), Color.red.opacity(0.6)]
        ]
        
        // Use weather/time context if available
        if let weather = run.weatherData {
            switch weather.timeOfDay {
            case .dawn, .morning:
                return LinearGradient(
                    colors: gradientVariations[0],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .evening:
                return LinearGradient(
                    colors: gradientVariations[1],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .night:
                return LinearGradient(
                    colors: gradientVariations[2],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            default:
                break
            }
        }
        
        // Use run ID hash for consistent selection
        let gradientIndex = abs(run.id.hashValue) % gradientVariations.count
        let selectedGradient = gradientVariations[gradientIndex]
        
        return LinearGradient(
            colors: selectedGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}



#Preview {
    let sampleRun = RunActivity(
        id: "1",
        name: "Morning Run in Golden Gate Park",
        date: Date(),
        distance: 5000,
        elapsedTime: 1800,
        averagePace: 360,
        startLocation: LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
        endLocation: LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
        routeCoordinates: [
            LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
            LocationData(latitude: 37.7949, longitude: -122.3994, timestamp: Date())
        ],
        city: "San Francisco",
        neighborhood: "Golden Gate Park"
    )
    
    let runWithMusic = RunActivity(
        id: "1",
        name: "Morning Run in Golden Gate Park",
        date: Date(),
        distance: 5000,
        elapsedTime: 1800,
        averagePace: 360,
        startLocation: LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
        endLocation: LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
        routeCoordinates: [
            LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
            LocationData(latitude: 37.7949, longitude: -122.3994, timestamp: Date())
        ],
        city: "San Francisco",
        neighborhood: "Golden Gate Park",
        spotifyTracks: [
            SpotifyTrack(id: "1", name: "Blinding Lights", artist: "The Weeknd", album: "After Hours", playedAt: Date(), durationMs: 200000, albumImageURL: nil),
            SpotifyTrack(id: "2", name: "Good 4 U", artist: "Olivia Rodrigo", album: "SOUR", playedAt: Date().addingTimeInterval(210), durationMs: 178000, albumImageURL: nil)
        ],
        powerSong: SpotifyTrack(id: "1", name: "Blinding Lights", artist: "The Weeknd", album: "After Hours", playedAt: Date(), durationMs: 200000, albumImageURL: nil),
        powerSongAveragePace: 340,
        weatherData: WeatherData(
            temperature: 72,
            condition: .clear,
            windSpeed: 5,
            humidity: 60,
            timeOfDay: .morning,
            description: "Clear sky",
            dataSource: .simulated
        )
    )
    
    RunCardView(run: runWithMusic)
        .padding()
        .frame(height: 250)
}