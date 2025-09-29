import SwiftUI

struct ShareableCardView: View {
    let run: RunActivity
    @StateObject private var userPreferences = UserPreferences.shared
    var transforms: ShareableCardTransforms?
    
    // Stat visibility toggles  
    var showDate: Bool = true
    var showTime: Bool = true
    var showPace: Bool = true
    var showTemperature: Bool = true
    
    // Font selection with fallback
    private var selectedFont: FontFamily {
        return run.fontFamily ?? FontFamily.default
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Photo background or gradient (positioned absolutely)
                if let photoBackground = run.backgroundPhoto {
                    PhotoBackgroundView(photoBackground: photoBackground)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                } else {
                    // Default gradient background
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.15),
                            Color.pink.opacity(0.08),
                            Color.purple.opacity(0.05),
                            Color(.systemBackground)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                
                // Main content - layout independent of background
                VStack(spacing: 0) {
                    // Header with stats moved to top-right
                    VStack(spacing: 16) {
                        headerWithStatsSection
                        
                        routeSection
                            .frame(maxHeight: geometry.size.height * 0.45) // Balanced size for route display
                            .zIndex(transforms?.routeZIndex ?? 0)
                            .onAppear {
                                print("🗺️ ========== ROUTE DISPLAY DEBUG ==========")
                                print("🗺️ Run: '\(run.name)'")
                                print("🗺️ Route coordinates count: \(run.routeCoordinates.count)")
                                if run.routeCoordinates.isEmpty {
                                    print("🗺️ ❌ NO ROUTE COORDINATES AVAILABLE")
                                } else {
                                    print("🗺️ ✅ Route coordinates available")
                                    print("🗺️ First coordinate: \(run.routeCoordinates.first?.latitude ?? 0), \(run.routeCoordinates.first?.longitude ?? 0)")
                                    print("🗺️ Last coordinate: \(run.routeCoordinates.last?.latitude ?? 0), \(run.routeCoordinates.last?.longitude ?? 0)")
                                }
                                print("🗺️ ==========================================")
                            }
                    }
                    
                    // Songs positioned at bottom with minimal spacing
                    Spacer(minLength: 10)
                    
                    if let tracks = run.spotifyTracks, !tracks.isEmpty, shouldShowSongs {
                        VStack(alignment: .leading, spacing: 0) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(tracks.filter { $0.isVisible }.enumerated()), id: \.offset) { index, track in
                                    let isPowerSong = run.powerSong?.id == track.id
                                    InstagramStyleTrackRow(
                                        track: track,
                                        index: index + 1,
                                        fontFamily: selectedFont,
                                        isPowerSong: isPowerSong
                                    )
                                }
                                
                                // Show "+N other songs" if there are hidden tracks
                                let hiddenCount = tracks.count - tracks.filter { $0.isVisible }.count
                                if hiddenCount > 0 {
                                    HStack(spacing: 6) {
                                        Text("+\(hiddenCount) other songs")
                                            .font(selectedFont.customFont(size: 10))
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
                            .scaleEffect(transforms?.trackListScale ?? 1.0)
                            .rotationEffect(transforms?.trackListRotation ?? .zero)
                            .offset(transforms?.trackListOffset ?? .zero)
                        }
                        .zIndex(transforms?.trackListZIndex ?? 1)
                    }
                }
                .padding(.top, 40) // Further reduced for better balance
                .padding(.horizontal, 24)
                .padding(.bottom, 0) // Remove bottom padding to match interactive view
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                
                // Album art displays (for export)
                if let albumArtDisplays = run.albumArtDisplays {
                    ForEach(albumArtDisplays.filter { $0.isVisible }, id: \.id) { albumArt in
                        AsyncImage(url: URL(string: albumArt.imageURL ?? "")) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120)
                                .cornerRadius(8)
                                .shadow(radius: 4)
                        } placeholder: {
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
                        }
                        .scaleEffect(albumArt.scale)
                        .rotationEffect(albumArt.rotation)
                        .offset(albumArt.offset)
                        .zIndex(albumArt.zIndex)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    
    private var shouldShowCity: Bool {
        run.showCity ?? userPreferences.showCityByDefault
    }
    
    private var shouldShowSongs: Bool {
        run.showSongs ?? userPreferences.showSongsByDefault
    }
    
    private var colorScheme: RunColorScheme {
        // Prioritize weather-based color, then user selection, then default
        run.weatherBasedRouteColor ?? 
        run.colorScheme ?? 
        userPreferences.defaultColorScheme
    }
    
    private var headerWithStatsSection: some View {
        VStack(spacing: 12) {
            // Top row: App branding and date with stats
            HStack {
                // Left side: App branding with watermark (flush with left edge)
                HStack {
                    Image("RTT_watermark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 14) // Adjust height to match text size
                        .opacity(0.7) // Subtle watermark appearance
                    Spacer()
                }
                .offset(x: -24) // Offset to counteract the horizontal padding
                
                Spacer()
                
                // Right side: Stats closer to right border
                HStack(spacing: 4) { // Tighter spacing
                    if showDate {
                        compactStatView(
                            icon: "calendar",
                            value: formatDateLowercase(run.date),
                            unit: ""
                        )
                    }
                    
                    if showTime {
                        compactStatView(
                            icon: "clock",
                            value: run.formattedDuration,
                            unit: ""
                        )
                    }
                    
                    if showPace {
                        compactStatView(
                            icon: "speedometer", 
                            value: userPreferences.formatPace(run.averagePace),
                            unit: "/\(userPreferences.distanceUnit.abbreviation)"
                        )
                    }
                    
                    if showTemperature, let weather = run.weatherData {
                        compactStatView(
                            icon: "thermometer",
                            value: userPreferences.formatTemperature(weather.temperature),
                            unit: ""
                        )
                    }
                }
                .fixedSize() // Prevent expansion, keep close to right edge
            }
            
            // Location right-aligned under stats
            HStack {
                Spacer()
                if let locationText = run.smartLocationDisplay, shouldShowCity {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.caption2)
                            .foregroundColor(colorScheme.primaryColor.color)
                        Text(locationText.lowercased())
                            .font(selectedFont.customFont(size: 11)) // Smaller to match stats size
                            .fontWeight(.medium)
                            .foregroundColor(colorScheme.primaryColor.color)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(colorScheme.primaryColor.color.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            
            // Mileage prominent with run name smaller (user request)
            VStack(spacing: 4) {
                Text("\(userPreferences.formatDistance(run.distance)) \(userPreferences.distanceUnit.abbreviation.lowercased())")
                    .font(selectedFont.customFont(size: 32))
                    .fontWeight(.heavy)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(colorScheme.gradient)
                
                Text(run.name.lowercased())
                    .font(selectedFont.customFont(size: 18))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundColor(colorScheme.primaryColor.color)
            }
        }
    }
    
    private func compactStatView(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 1) { // Reduced spacing for more room
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Combine value and unit into single Text to prevent line breaks
            Text(value + (!unit.isEmpty ? unit : ""))
                .font(selectedFont.customFont(size: 9)) // Slightly smaller for more room
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5) // More aggressive scaling to fit everything
                .truncationMode(.tail) // Truncate long text gracefully
                .fixedSize(horizontal: false, vertical: true) // Allow horizontal compression but prevent vertical expansion
        }
    }
    
    private var routeSection: some View {
        VStack {
            let songPositions = generateSongPositions()
            
            RoutePathView(
                coordinates: run.routeCoordinates,
                songPositions: shouldShowSongs ? songPositions : [],
                lineWidth: 4,
                showSongIndicators: shouldShowSongs && !songPositions.isEmpty,
                colorScheme: colorScheme
            )
            .padding(.horizontal, 8)
            .scaleEffect(transforms?.routeScale ?? 1.0)
            .rotationEffect(transforms?.routeRotation ?? .zero)
            .offset(transforms?.routeOffset ?? .zero)
        }
    }
    
    private var statsSection: some View {
        HStack(spacing: 0) {
            StatView(
                icon: "figure.run",
                value: userPreferences.formatDistance(run.distance),
                unit: userPreferences.distanceUnit.displayName,
                color: .orange,
                fontFamily: selectedFont
            )
            
            Divider()
                .frame(height: 40)
            
            StatView(
                icon: "clock",
                value: run.formattedDuration,
                unit: "time",
                color: .blue,
                fontFamily: selectedFont
            )
            
            Divider()
                .frame(height: 40)
            
            StatView(
                icon: "speedometer",
                value: userPreferences.formatPace(run.averagePace),
                unit: "/" + userPreferences.distanceUnit.displayName.dropLast(),
                color: .green,
                fontFamily: selectedFont
            )
        }
        .padding(.horizontal)
    }
    
    
    private func generateSongPositions() -> [SongPosition] {
        guard let tracks = run.spotifyTracks,
              !tracks.isEmpty,
              !run.routeCoordinates.isEmpty else {
            return []
        }
        
        let runDuration = run.elapsedTime
        let sortedTracks = tracks.sorted { $0.playedAt < $1.playedAt }
        
        // Separate tracks into pre-run and during-run
        let preRunTracks = sortedTracks.filter { track in
            track.playedAt.timeIntervalSince(run.date) < 0
        }
        
        let duringRunTracks = sortedTracks.filter { track in
            track.playedAt.timeIntervalSince(run.date) >= 0
        }
        
        var finalTracks: [SpotifyTrack] = []
        
        // Check if we need to include a pre-run song
        if let firstDuringRunTrack = duringRunTracks.first {
            let firstTrackStartTime = firstDuringRunTrack.playedAt.timeIntervalSince(run.date)
            
            if firstTrackStartTime <= 30 {
                // Case 2: New song starts within 30 seconds, use it as first song
                finalTracks = duringRunTracks
            } else {
                // Case 3: Gap at beginning - look for pre-run song that might have been playing
                if let lastPreRunTrack = preRunTracks.last {
                    let trackStartTime = lastPreRunTrack.playedAt.timeIntervalSince(run.date)
                    let estimatedTrackEnd = trackStartTime + Double(lastPreRunTrack.durationMs) / 1000.0
                    
                    // If the pre-run song would have been playing for >30 seconds during the run
                    if estimatedTrackEnd > 30 {
                        // Case 1: Include the pre-run song as first song
                        finalTracks = [lastPreRunTrack] + duringRunTracks
                    } else {
                        // Pre-run song ended too early, just use during-run tracks
                        finalTracks = duringRunTracks
                    }
                } else {
                    // No pre-run tracks available
                    finalTracks = duringRunTracks
                }
            }
        } else {
            // No during-run tracks, check if we have a pre-run song that extends into the run
            if let lastPreRunTrack = preRunTracks.last {
                let trackStartTime = lastPreRunTrack.playedAt.timeIntervalSince(run.date)
                let estimatedTrackEnd = trackStartTime + Double(lastPreRunTrack.durationMs) / 1000.0
                
                if estimatedTrackEnd > 30 {
                    finalTracks = [lastPreRunTrack]
                }
            }
        }
        
        let visibleTracks = finalTracks.filter { $0.isVisible }
        
        return visibleTracks.enumerated().compactMap { index, track in
            let trackStartTime = track.playedAt.timeIntervalSince(run.date)
            
            // Position pre-run songs (negative start time) at the beginning
            // Position songs that started within 30 seconds at the beginning  
            let adjustedStartTime = trackStartTime <= 30 ? 0 : trackStartTime
            
            let progressRatio = max(0, min(1, adjustedStartTime / runDuration))
            
            // Check if this track is the Power Song
            let isPowerSong = run.powerSong?.id == track.id
            return SongPosition(songIndex: index, progressRatio: progressRatio, isPowerSong: isPowerSong)
        }
    }
    
    private func formatDateLowercase(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).lowercased()
    }
}

struct StatView: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    let fontFamily: FontFamily
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(spacing: 2) {
                Text(value)
                    .font(fontFamily.customFont(size: 20))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(unit)
                    .font(fontFamily.customFont(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SongRowView: View {
    let track: SpotifyTrack
    let index: Int
    let isFavorite: Bool
    let fontFamily: FontFamily
    
    var body: some View {
        HStack(spacing: 8) {
            Text(romanNumeral(for: index))
                .font(fontFamily.customFont(size: 10))
                .fontWeight(.bold)
                .foregroundColor(.orange)
                .frame(width: 16, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(fontFamily.customFont(size: 12))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(track.artist)
                    .font(fontFamily.customFont(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground).opacity(0.8))
        .cornerRadius(8)
    }
    
    private func romanNumeral(for number: Int) -> String {
        let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        let numerals = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
        
        var num = number
        var result = ""
        
        for (index, value) in values.enumerated() {
            let count = num / value
            if count > 0 {
                result += String(repeating: numerals[index], count: count)
                num %= value
            }
        }
        
        return result
    }
}

struct CompactSongRowView: View {
    let track: SpotifyTrack
    let index: Int
    let fontFamily: FontFamily
    
    var body: some View {
        HStack(spacing: 6) {
            Text(romanNumeral(for: index))
                .font(fontFamily.customFont(size: 8))
                .fontWeight(.bold)
                .foregroundColor(.green)
                .frame(width: 12, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(fontFamily.customFont(size: 10))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                
                Text(track.artist)
                    .font(fontFamily.customFont(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if track.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color(.secondarySystemBackground).opacity(0.6))
        .cornerRadius(6)
    }
    
    private func romanNumeral(for number: Int) -> String {
        let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        let numerals = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
        
        var num = number
        var result = ""
        
        for (index, value) in values.enumerated() {
            let count = num / value
            if count > 0 {
                result += String(repeating: numerals[index], count: count)
                num %= value
            }
        }
        
        return result
    }
}

#Preview {
    let sampleTracks = [
        SpotifyTrack(id: "1", name: "Blinding Lights", artist: "The Weeknd", album: "After Hours", playedAt: Date(), durationMs: 200000, albumImageURL: nil, isFavorite: true),
        SpotifyTrack(id: "2", name: "Good 4 U", artist: "Olivia Rodrigo", album: "SOUR", playedAt: Date().addingTimeInterval(210), durationMs: 178000, albumImageURL: nil),
        SpotifyTrack(id: "3", name: "Levitating", artist: "Dua Lipa", album: "Future Nostalgia", playedAt: Date().addingTimeInterval(400), durationMs: 203000, albumImageURL: nil),
        SpotifyTrack(id: "4", name: "Heat Waves", artist: "Glass Animals", album: "Dreamland", playedAt: Date().addingTimeInterval(610), durationMs: 238000, albumImageURL: nil)
    ]
    
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
            LocationData(latitude: 37.7949, longitude: -122.3994, timestamp: Date()),
            LocationData(latitude: 37.8049, longitude: -122.3894, timestamp: Date()),
            LocationData(latitude: 37.8149, longitude: -122.3794, timestamp: Date())
        ],
        city: "San Francisco",
        neighborhood: "Golden Gate Park",
        spotifyTracks: sampleTracks
    )
    
    ShareableCardView(run: sampleRun)
        .aspectRatio(9.0/16.0, contentMode: .fit)
        .padding()
}