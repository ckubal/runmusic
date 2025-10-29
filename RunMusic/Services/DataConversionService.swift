import Foundation
import CoreLocation
import MapKit

class DataConversionService {
    static let shared = DataConversionService()
    
    private init() {}
    
    // Debug logging control - set to true only when debugging
    private let debugLoggingEnabled = false
    
    private func debugLog(_ message: String) {
        if debugLoggingEnabled {
            print(message)
        }
    }
    
    func convertStravaActivityToRunActivity(_ stravaActivity: StravaActivity, detailedActivity: StravaDetailedActivity? = nil, streams: [StravaStream]? = nil, skipHeavyCalculations: Bool = false) async -> RunActivity {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("🏃 DataConversionService: Converting activity '\(stravaActivity.name)' (ID: \(stravaActivity.id)) [skipHeavy: \(skipHeavyCalculations)]")
        
        let dateFormatter = ISO8601DateFormatter()
        
        // Parse the start_date as UTC, then convert to local time using UTC offset
        let utcDate = dateFormatter.date(from: stravaActivity.startDate) ?? Date()
        let finalDate: Date
        
        if let detailedActivity = detailedActivity, let utcOffset = detailedActivity.utcOffset {
            // The UTC offset tells us how many seconds the local time zone is offset from UTC
            // For Pacific Time in summer (PDT), utcOffset = -25200 (UTC-7)
            // Since Strava gives us UTC time, we DON'T add the offset - the Date object already represents the correct moment in time
            finalDate = utcDate
            if debugLoggingEnabled {
                debugLog("🕐 Timezone analysis:")
                debugLog("  - Strava UTC time: \(utcDate)")
                debugLog("  - UTC offset from Strava: \(utcOffset) seconds (\(utcOffset/3600) hours)")
                
                // Show what this looks like in different timezones for debugging
                let utcFormatter = DateFormatter()
                utcFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                utcFormatter.timeZone = TimeZone(abbreviation: "UTC")
                
                let pacificFormatter = DateFormatter()
                pacificFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                pacificFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
                
                debugLog("  - As UTC: \(utcFormatter.string(from: finalDate))")
                debugLog("  - As Pacific: \(pacificFormatter.string(from: finalDate)) (this should match your actual run time)")
            }
            
        } else {
            finalDate = utcDate
            debugLog("⚠️ No UTC offset available, using UTC time: \(utcDate)")
        }
        
        let date = finalDate
        
        // Log basic activity data (only when debugging)
        if debugLoggingEnabled {
            debugLog("📍 Activity basic data:")
            debugLog("  - Name: \(stravaActivity.name)")
            debugLog("  - Distance: \(stravaActivity.distance)m")
            debugLog("  - Start lat/lng: \(stravaActivity.startLatlng?.description ?? "nil")")
            debugLog("  - End lat/lng: \(stravaActivity.endLatlng?.description ?? "nil")")
            debugLog("  - Map polyline: \(stravaActivity.map?.polyline != nil ? "EXISTS (\(stravaActivity.map!.polyline!.count) chars)" : "nil")")
        }
        
        let startLocation = stravaActivity.startLatlng?.count == 2 ? LocationData(
            latitude: stravaActivity.startLatlng![0],
            longitude: stravaActivity.startLatlng![1],
            timestamp: date
        ) : nil
        
        let endLocation = stravaActivity.endLatlng?.count == 2 ? LocationData(
            latitude: stravaActivity.endLatlng![0],
            longitude: stravaActivity.endLatlng![1],
            timestamp: date.addingTimeInterval(TimeInterval(stravaActivity.elapsedTime))
        ) : nil
        
        var routeCoordinates: [LocationData] = []
        
        debugLog("🗺️ ========== ROUTE DATA PROCESSING ==========")
        if let streams = streams {
            debugLog("📈 Processing streams data...")
            routeCoordinates = extractRouteCoordinatesFromStreams(streams, startDate: date)
            debugLog("📈 Extracted \(routeCoordinates.count) coordinates from streams")
        } else if let detailedPolyline = detailedActivity?.map?.polyline, !detailedPolyline.isEmpty {
            debugLog("🗺️ Processing detailed activity polyline data (length: \(detailedPolyline.count))...")
            routeCoordinates = decodePolyline(detailedPolyline, startDate: date)
            debugLog("🗺️ Decoded \(routeCoordinates.count) coordinates from detailed polyline")
        } else if let basicPolyline = stravaActivity.map?.polyline, !basicPolyline.isEmpty {
            debugLog("🗺️ Processing basic activity polyline data (length: \(basicPolyline.count))...")
            routeCoordinates = decodePolyline(basicPolyline, startDate: date)
            debugLog("🗺️ Decoded \(routeCoordinates.count) coordinates from basic polyline")
        } else {
            if debugLoggingEnabled {
                debugLog("❌ ========== ROUTE DEBUG - NO DATA ===========")
                debugLog("❌ No route data available:")
                debugLog("❌   - Streams: \(streams != nil ? "PROVIDED" : "nil")")
                debugLog("❌   - Detailed polyline: \(detailedActivity?.map?.polyline?.isEmpty == false ? "EXISTS (\(detailedActivity?.map?.polyline?.count ?? 0) chars)" : "MISSING/EMPTY")")
                debugLog("❌   - Basic polyline: \(stravaActivity.map?.polyline?.isEmpty == false ? "EXISTS (\(stravaActivity.map?.polyline?.count ?? 0) chars)" : "MISSING/EMPTY")")
                debugLog("❌ =============================================")
            }
        }
        debugLog("🗺️ Final route coordinates count: \(routeCoordinates.count)")
        debugLog("🗺️ ===============================================")
        
        let averagePace = stravaActivity.distance > 0 ? Double(stravaActivity.movingTime) / (stravaActivity.distance / 1000.0) : 0
        
        // Log detailed activity data (only when debugging)
        if debugLoggingEnabled {
            if let detailed = detailedActivity {
                debugLog("🔍 Detailed activity data:")
                debugLog("  - Location city: \(detailed.locationCity ?? "nil")")
                debugLog("  - Location state: \(detailed.locationState ?? "nil")")
                debugLog("  - Location country: \(detailed.locationCountry ?? "nil")")
                debugLog("  - Map polyline: \(detailed.map?.polyline != nil ? "EXISTS (\(detailed.map!.polyline!.count) chars)" : "nil")")
                debugLog("  - Map summary polyline: \(detailed.map?.summaryPolyline != nil ? "EXISTS (\(detailed.map!.summaryPolyline!.count) chars)" : "nil")")
            } else {
                debugLog("⚠️ No detailed activity data provided")
            }
        }
        
        // Try to get city from Strava data first, then fall back to coordinate-based lookup
        var city = detailedActivity?.locationCity
        let neighborhood = detailedActivity?.locationState
        
        // If no city from Strava and we have start coordinates, use reverse geocoding
        if city == nil, let startLat = stravaActivity.startLatlng?.first, let startLon = stravaActivity.startLatlng?.last {
            debugLog("🌍 No city from Strava, attempting reverse geocoding: \(startLat), \(startLon)")
            city = await reverseGeocodeCoordinates(latitude: startLat, longitude: startLon)
        }
        
        // Perform smart location analysis using the full route
        debugLog("🗺️ Starting smart location analysis...")
        let locationAnalysis = await LocationAnalysisService.shared.analyzeRunLocation(for: routeCoordinates)
        
        var runActivity = RunActivity(
            id: String(stravaActivity.id),
            name: stravaActivity.name,
            date: date,
            distance: stravaActivity.distance,
            elapsedTime: TimeInterval(stravaActivity.elapsedTime),
            averagePace: averagePace,
            startLocation: startLocation,
            endLocation: endLocation,
            routeCoordinates: routeCoordinates,
            city: city,
            neighborhood: neighborhood,
            locationAnalysis: locationAnalysis,
            spotifyTracks: nil,
            powerSong: nil,
            powerSongAveragePace: nil
        )
        
        if debugLoggingEnabled {
            debugLog("✅ Created RunActivity with:")
            debugLog("  - City: \(city ?? "nil")")
            debugLog("  - Route coordinates: \(routeCoordinates.count)")
            debugLog("  - Start location: \(startLocation != nil ? "EXISTS" : "nil")")
            if routeCoordinates.isEmpty {
                debugLog("❌ No route coordinates! Polyline issues:")
                debugLog("  - Basic activity polyline: \(stravaActivity.map?.polyline?.isEmpty == false ? "EXISTS" : "MISSING")")
                debugLog("  - Detailed activity polyline: \(detailedActivity?.map?.polyline?.isEmpty == false ? "EXISTS" : "MISSING")")
            } else {
                debugLog("✅ Route coordinates sample: \(routeCoordinates.prefix(3))")
            }
        }
        
        // Fetch weather data for the run if we have location data
        if let startLocation = startLocation {
            debugLog("🌤️ Fetching weather data for run at \(date)...")
            
            // Visual Crossing supports historical weather data
            // Only use real API data for testing
            do {
                runActivity.weatherData = try await WeatherService.shared.fetchWeatherData(
                    for: startLocation.coordinate,
                    on: date
                )
                debugLog("✅ Visual Crossing weather data fetched: \(runActivity.weatherData!.temperature)°F, \(runActivity.weatherData!.condition.rawValue)")
            } catch {
                debugLog("⚠️ Visual Crossing API error: \(error.localizedDescription)")
                debugLog("🌤️ Falling back to simulated weather data...")
                // Use simulated weather as fallback to ensure weather always shows
                runActivity.weatherData = WeatherService.shared.simulateWeatherData(
                    for: startLocation.coordinate,
                    on: date
                )
                debugLog("✅ Simulated weather data: \(runActivity.weatherData!.temperature)°F, \(runActivity.weatherData!.condition.rawValue)")
            }
            
            // If weather suggests a different color scheme, log it
            if let suggestedColor = runActivity.weatherBasedRouteColor {
                debugLog("🎨 Weather suggests route color: \(suggestedColor.name)")
            }
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let processingTime = endTime - startTime
        debugLog("🏃 ⏱️ PERFORMANCE: Converted '\(stravaActivity.name)' in \(String(format: "%.2f", processingTime))s")
        
        return runActivity
    }
    
    // MARK: - Power Song Analysis
    
    /// Analyzes run data using coordinates to find the song during which the runner had their fastest average pace
    func calculatePowerSong(for runActivity: inout RunActivity, from streams: [StravaStream]) {
        // PERFORMANCE OPTIMIZATION: Skip if power song already exists (from cache)
        if runActivity.powerSong != nil {
            debugLog("🎵 ⚡ SKIPPING: Power song already calculated for '\(runActivity.name)'")
            return
        }
        
        print("🔥 POWER SONG CALCULATION START for run: \(runActivity.name)")
        print("🔥 STREAMS: Received \(streams.count) stream types")
        for stream in streams {
            print("🔥 STREAM TYPE: \(stream.type) with \(stream.data.count) data points")
        }
        
        guard let spotifyTracks = runActivity.spotifyTracks, !spotifyTracks.isEmpty else {
            print("🔥 POWER SONG FAIL: No Spotify tracks available for power song analysis")
            debugLog("🎵 No Spotify tracks available for power song analysis")
            return
        }
        
        print("🔥 POWER SONG: Found \(spotifyTracks.count) Spotify tracks")
        
        debugLog("🎵 Starting coordinate-based power song analysis with \(spotifyTracks.count) tracks...")
        
        // Reuse existing coordinate extraction logic that works for route display
        let locationData = extractRouteCoordinatesFromStreams(streams, startDate: runActivity.date)
        
        guard !locationData.isEmpty else {
            debugLog("🎵 No coordinate data found for power song analysis")
            return
        }
        
        debugLog("🎵 Successfully extracted \(locationData.count) coordinate points")
        
        // Convert LocationData to time-indexed coordinates for efficient lookup
        var timeCoordinates: [(time: TimeInterval, coordinate: CLLocationCoordinate2D)] = []
        for (index, location) in locationData.enumerated() {
            if let timestamp = location.timestamp {
                let timeOffset = timestamp.timeIntervalSince(runActivity.date)
                timeCoordinates.append((time: timeOffset, coordinate: location.coordinate))
                
                // Debug first few coordinates
                if debugLoggingEnabled && index < 3 {
                    debugLog("🎵 COORDINATE DEBUG \(index): time offset = \(timeOffset)s")
                }
            } else {
                if debugLoggingEnabled && index < 3 {
                    debugLog("🎵 COORDINATE DEBUG \(index): ❌ No timestamp!")
                }
            }
        }
        
        guard !timeCoordinates.isEmpty else {
            debugLog("🎵 No valid time-indexed coordinates found")
            return
        }
        
        let runDuration = timeCoordinates.map { $0.time }.max() ?? 0
        debugLog("🎵 Run duration calculated from coordinates: \(runDuration)s (\(runDuration/60) minutes)")
        
        var bestTrack: SpotifyTrack?
        var fastestPace: Double = Double.infinity // Lower is better (minutes per mile)
        
        for track in spotifyTracks {
            // Calculate song start and end times relative to run start
            let songStartTime = track.playedAt
            let songEndTime = songStartTime.addingTimeInterval(TimeInterval(track.durationMs / 1000))
            
            // Convert to time offsets from run start
            let startOffset = songStartTime.timeIntervalSince(runActivity.date)
            let endOffset = songEndTime.timeIntervalSince(runActivity.date)
            let runDuration = timeCoordinates.last?.time ?? 0
            
            // Debug timing information for first few tracks
            if debugLoggingEnabled, let trackIndex = spotifyTracks.firstIndex(where: { $0.id == track.id }), trackIndex < 3 {
                debugLog("🎵 TIMING DEBUG for \"\(track.name)\":")
                debugLog("   - Run start: \(runActivity.date)")
                debugLog("   - Song played at: \(songStartTime)")
                debugLog("   - Start offset: \(startOffset)s")
                debugLog("   - End offset: \(endOffset)s") 
                debugLog("   - Run duration: \(runDuration)s")
            }
            
            // Skip if song is entirely outside run time bounds
            if startOffset < 0 && endOffset < 0 {
                debugLog("🎵 \"\(track.name)\" by \(track.artist): played before run started")
                continue
            }
            if startOffset > runDuration {
                debugLog("🎵 \"\(track.name)\" by \(track.artist): played after run ended")
                continue
            }
            
            // Find closest coordinates for song start and end using binary search
            let startCoord = findClosestCoordinate(at: max(0, startOffset), in: timeCoordinates)
            let endCoord = findClosestCoordinate(at: min(endOffset, timeCoordinates.last!.time), in: timeCoordinates)
            
            guard let startPoint = startCoord, let endPoint = endCoord else {
                debugLog("🎵 \"\(track.name)\" by \(track.artist): could not find coordinates for song timeframe")
                continue
            }
            
            // Calculate distance covered during song using Haversine formula
            let distance = calculateDistance(from: startPoint.coordinate, to: endPoint.coordinate,
                                           using: timeCoordinates, startTime: startPoint.time, endTime: endPoint.time)
            
            // Calculate time duration for this segment
            let duration = endPoint.time - startPoint.time
            
            if duration > 0 && distance > 0 {
                // Convert to pace in minutes per mile
                let metersPerSecond = distance / duration
                let milesPerHour = metersPerSecond * 2.23694 // Convert m/s to mph
                let minutesPerMile = milesPerHour > 0 ? 60.0 / milesPerHour : Double.infinity
                
                let paceMinutes = Int(minutesPerMile)
                let paceSeconds = Int((minutesPerMile - Double(paceMinutes)) * 60)
                debugLog("🎵 \"\(track.name)\" by \(track.artist): \(paceMinutes):\(String(format: "%02d", paceSeconds)) per mile pace")
                
                // Check if this is the fastest pace so far
                if minutesPerMile < fastestPace && minutesPerMile > 0 {
                    fastestPace = minutesPerMile
                    bestTrack = track
                }
            } else {
                debugLog("🎵 \"\(track.name)\" by \(track.artist): insufficient data for pace calculation")
            }
        }
        
        // Store the power song result
        if let powerTrack = bestTrack, fastestPace != Double.infinity {
            runActivity.powerSong = powerTrack
            // Convert minutes per mile to seconds per km for storage
            let secondsPerMile = fastestPace * 60.0  // minutes to seconds
            let secondsPerKm = secondsPerMile / 1.60934  // mile to km conversion
            runActivity.powerSongAveragePace = secondsPerKm
            
            let paceMinutes = Int(fastestPace)
            let paceSeconds = Int((fastestPace - Double(paceMinutes)) * 60)
            debugLog("🎵 ⚡ POWER SONG: \"\(powerTrack.name)\" by \(powerTrack.artist) at \(paceMinutes):\(String(format: "%02d", paceSeconds)) per mile pace")
        } else {
            debugLog("🎵 No power song could be determined from available data")
        }
    }
    
    // MARK: - Helper Methods for Power Song Calculation
    
    private func findClosestCoordinate(at targetTime: TimeInterval, 
                                     in coordinates: [(time: TimeInterval, coordinate: CLLocationCoordinate2D)]) 
                                     -> (time: TimeInterval, coordinate: CLLocationCoordinate2D)? {
        guard !coordinates.isEmpty else { return nil }
        
        // Binary search for closest time
        var left = 0
        var right = coordinates.count - 1
        
        while left < right {
            let mid = (left + right) / 2
            if coordinates[mid].time < targetTime {
                left = mid + 1
            } else {
                right = mid
            }
        }
        
        // Check if we need the previous point instead
        if left > 0 {
            let prevDiff = abs(coordinates[left - 1].time - targetTime)
            let currDiff = abs(coordinates[left].time - targetTime)
            if prevDiff < currDiff {
                return coordinates[left - 1]
            }
        }
        
        return coordinates[left]
    }
    
    private func calculateDistance(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D,
                                 using coordinates: [(time: TimeInterval, coordinate: CLLocationCoordinate2D)],
                                 startTime: TimeInterval, endTime: TimeInterval) -> Double {
        // Find all coordinates between start and end times
        let segmentCoords = coordinates.filter { $0.time >= startTime && $0.time <= endTime }
        
        guard segmentCoords.count >= 2 else {
            // If we only have start and end, calculate direct distance
            return haversineDistance(from: start, to: end)
        }
        
        // Calculate total distance by summing segments
        var totalDistance: Double = 0
        for i in 1..<segmentCoords.count {
            let dist = haversineDistance(from: segmentCoords[i-1].coordinate, to: segmentCoords[i].coordinate)
            totalDistance += dist
        }
        
        return totalDistance
    }
    
    private func haversineDistance(from coord1: CLLocationCoordinate2D, to coord2: CLLocationCoordinate2D) -> Double {
        let earthRadius = 6371000.0 // Earth's radius in meters
        
        let lat1Rad = coord1.latitude * .pi / 180
        let lat2Rad = coord2.latitude * .pi / 180
        let deltaLat = (coord2.latitude - coord1.latitude) * .pi / 180
        let deltaLon = (coord2.longitude - coord1.longitude) * .pi / 180
        
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        
        return earthRadius * c
    }
    
    // MARK: - Reverse Geocoding
    
    private func reverseGeocodeCoordinates(latitude: Double, longitude: Double) async -> String? {
        return await withCheckedContinuation { continuation in
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let geocoder = CLGeocoder()
            
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    print("🌍 Reverse geocoding failed: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    print("🌍 No placemark found for coordinates")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Try to get the most specific city name available
                let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
                print("🌍 Reverse geocoding result: \(city ?? "no city found")")
                continuation.resume(returning: city)
            }
        }
    }
    
    
    private func extractRouteCoordinatesFromStreams(_ streams: [StravaStream], startDate: Date) -> [LocationData] {
        guard let latlngStream = streams.first(where: { $0.type == "latlng" }),
              let timeStream = streams.first(where: { $0.type == "time" }) else {
            return []
        }
        
        var coordinates: [LocationData] = []
        
        // Debug time stream format (only when debugging)
        if debugLoggingEnabled {
            debugLog("🕐 TIME STREAM DEBUG: Found time stream with \(timeStream.data.count) data points")
            for (debugIndex, timeData) in timeStream.data.prefix(5).enumerated() {
                switch timeData {
                case .int(let seconds):
                    debugLog("🕐 Time[\(debugIndex)]: .int(\(seconds))")
                case .double(let seconds):
                    debugLog("🕐 Time[\(debugIndex)]: .double(\(seconds))")
                case .coordinate(let coords):
                    debugLog("🕐 Time[\(debugIndex)]: .coordinate(\(coords)) - UNEXPECTED!")
                }
            }
        }
        
        for (index, coordData) in latlngStream.data.enumerated() {
            if case .coordinate(let coord) = coordData, coord.count == 2 {
                let timeOffset: TimeInterval
                if index < timeStream.data.count {
                    switch timeStream.data[index] {
                    case .int(let seconds):
                        timeOffset = TimeInterval(seconds)
                    case .double(let seconds):
                        timeOffset = TimeInterval(seconds)
                    default:
                        timeOffset = 0
                        if index < 3 {
                            print("🕐 WARNING: Unexpected time data format at index \(index): \(timeStream.data[index])")
                        }
                    }
                } else {
                    timeOffset = 0
                }
                
                let timestamp = startDate.addingTimeInterval(timeOffset)
                let locationData = LocationData(
                    latitude: coord[0],
                    longitude: coord[1],
                    timestamp: timestamp
                )
                coordinates.append(locationData)
                
                // Debug first few coordinates
                if index < 3 {
                    print("🕐 EXTRACTED Time[\(index)]: offset=\(timeOffset)s, timestamp=\(timestamp)")
                }
            }
        }
        
        return coordinates
    }
    
    private func decodePolyline(_ polyline: String, startDate: Date) -> [LocationData] {
        do {
            let coordinates = try decodePolylineCoordinatesSafely(polyline)
            return coordinates.enumerated().map { index, coord in
                let timeOffset = TimeInterval(index * 10)
                return LocationData(
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    timestamp: startDate.addingTimeInterval(timeOffset)
                )
            }
        } catch {
            print("❌ Failed to decode polyline: \(error)")
            return []
        }
    }
    
    private func decodePolylineCoordinates(_ polyline: String) -> [CLLocationCoordinate2D] {
        guard !polyline.isEmpty else {
            print("⚠️ Empty polyline string, returning empty coordinates")
            return []
        }
        
        guard let data = polyline.data(using: .utf8) else {
            print("❌ Failed to convert polyline to UTF-8 data")
            return []
        }
        
        var coordinates: [CLLocationCoordinate2D] = []
        var index = 0
        var lat = 0
        var lng = 0
        
        while index < data.count {
            var byte: Int
            var shift = 0
            var result = 0
            
            // Decode latitude delta
            repeat {
                guard index < data.count else {
                    print("❌ Polyline decoding: index out of bounds while reading latitude")
                    return coordinates
                }
                byte = Int(data[index])
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20 && index < data.count
            
            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat
            
            shift = 0
            result = 0
            
            // Decode longitude delta
            repeat {
                guard index < data.count else {
                    print("❌ Polyline decoding: index out of bounds while reading longitude")
                    return coordinates
                }
                byte = Int(data[index])
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20 && index < data.count
            
            let deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += deltaLng
            
            let coordinate = CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            )
            coordinates.append(coordinate)
        }
        
        return coordinates
    }
    
    private func decodePolylineCoordinatesSafely(_ polyline: String) throws -> [CLLocationCoordinate2D] {
        guard !polyline.isEmpty else {
            print("⚠️ Empty polyline string, returning empty coordinates")
            return []
        }
        
        print("🗺️ Polyline decoding attempt: length=\(polyline.count)")
        
        var coordinates: [CLLocationCoordinate2D] = []
        var index = polyline.startIndex
        var lat = 0
        var lng = 0
        var coordinateCount = 0
        
        // Use String.Index for safer character iteration
        while index < polyline.endIndex {
            coordinateCount += 1
            if coordinateCount > 10000 { // Safety limit for very long polylines
                print("⚠️ Coordinate limit reached, stopping decode at \(coordinates.count) points")
                break
            }
            
            // Decode latitude
            var shift = 0
            var result = 0
            var byte: Int
            
            repeat {
                guard index < polyline.endIndex else {
                    print("🗺️ Reached end while decoding latitude, returning \(coordinates.count) coordinates")
                    return coordinates
                }
                
                let character = polyline[index]
                byte = Int(character.asciiValue ?? 0) - 63
                index = polyline.index(after: index)
                
                result |= (byte & 0x1F) << shift
                shift += 5
                
                if shift > 30 { // More reasonable limit
                    print("❌ Latitude decoding shift limit exceeded (\(shift) bits), aborting")
                    return coordinates
                }
            } while byte >= 0x20 && index < polyline.endIndex
            
            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat
            
            // Decode longitude
            shift = 0
            result = 0
            
            repeat {
                guard index < polyline.endIndex else {
                    print("🗺️ Reached end while decoding longitude, returning \(coordinates.count) coordinates")
                    return coordinates
                }
                
                let character = polyline[index]
                byte = Int(character.asciiValue ?? 0) - 63
                index = polyline.index(after: index)
                
                result |= (byte & 0x1F) << shift
                shift += 5
                
                if shift > 30 { // More reasonable limit
                    print("❌ Longitude decoding shift limit exceeded (\(shift) bits), aborting")
                    return coordinates
                }
            } while byte >= 0x20 && index < polyline.endIndex
            
            let deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += deltaLng
            
            let coordinate = CLLocationCoordinate2D(
                latitude: Double(lat) / 1e5,
                longitude: Double(lng) / 1e5
            )
            
            // Validate coordinate is reasonable for earth coordinates
            if abs(coordinate.latitude) <= 90 && abs(coordinate.longitude) <= 180 {
                coordinates.append(coordinate)
                
                // Debug first few coordinates
                if coordinates.count <= 3 {
                    print("🗺️ Coordinate \(coordinates.count): \(coordinate.latitude), \(coordinate.longitude)")
                }
            } else {
                print("⚠️ Invalid coordinate \(coordinateCount): lat=\(coordinate.latitude), lng=\(coordinate.longitude) - skipping")
            }
        }
        
        print("🗺️ Successfully decoded \(coordinates.count) coordinates from polyline")
        return coordinates
    }
    
    func convertSpotifyTrackToSpotifyTrack(_ spotifyTrack: SpotifyPlayHistoryItem) -> SpotifyTrack {
        debugLog("🕐 ========== TIMESTAMP PARSING DEBUG ===========")
        debugLog("🕐 Raw playedAt string: '\(spotifyTrack.playedAt)'")
        
        // Try multiple date formatters for different possible formats
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let iso8601FormatterNoFraction = ISO8601DateFormatter()
        iso8601FormatterNoFraction.formatOptions = [.withInternetDateTime]
        
        let customFormatter = DateFormatter()
        customFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        customFormatter.timeZone = TimeZone(abbreviation: "UTC")
        
        let customFormatterNoFraction = DateFormatter()
        customFormatterNoFraction.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        customFormatterNoFraction.timeZone = TimeZone(abbreviation: "UTC")
        
        let playedAt: Date
        if let date = iso8601Formatter.date(from: spotifyTrack.playedAt) {
            playedAt = date
            debugLog("✅ Parsed with ISO8601 (with fractional seconds): \(playedAt)")
        } else if let date = iso8601FormatterNoFraction.date(from: spotifyTrack.playedAt) {
            playedAt = date
            debugLog("✅ Parsed with ISO8601 (no fractional seconds): \(playedAt)")
        } else if let date = customFormatter.date(from: spotifyTrack.playedAt) {
            playedAt = date
            debugLog("✅ Parsed with custom formatter (with fractional): \(playedAt)")
        } else if let date = customFormatterNoFraction.date(from: spotifyTrack.playedAt) {
            playedAt = date
            debugLog("✅ Parsed with custom formatter (no fractional): \(playedAt)")
        } else {
            playedAt = Date()
            // Keep error logging for timestamp failures as they are critical
            print("❌ FAILED TO PARSE TIMESTAMP - falling back to current time: \(playedAt)")
            print("❌ This is the root cause of the timestamp issue!")
        }
        
        // Show timezone information for debugging (only when debugging enabled)
        if debugLoggingEnabled {
            let utcFormatter = DateFormatter()
            utcFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            utcFormatter.timeZone = TimeZone(abbreviation: "UTC")
            
            let pacificFormatter = DateFormatter()
            pacificFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            pacificFormatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
            
            debugLog("🌍 Timezone comparison:")
            debugLog("  - UTC: \(utcFormatter.string(from: playedAt))")
            debugLog("  - Pacific: \(pacificFormatter.string(from: playedAt))")
            debugLog("  - System timezone: \(TimeZone.current.identifier)")
        }
        debugLog("🕐 ===============================================")
        
        let artistName = spotifyTrack.track.artists.first?.name ?? "Unknown Artist"
        let albumImageURL = spotifyTrack.track.album.images.first?.url
        
        // Debug album art extraction (simplified)
        if debugLoggingEnabled && albumImageURL == nil {
            debugLog("⚠️ No album art for '\(spotifyTrack.track.name)' by \(artistName) (album: '\(spotifyTrack.track.album.name)')")
        }
        
        return SpotifyTrack(
            id: spotifyTrack.track.id,
            name: spotifyTrack.track.name,
            artist: artistName,
            album: spotifyTrack.track.album.name,
            playedAt: playedAt,
            durationMs: spotifyTrack.track.durationMs,
            albumImageURL: albumImageURL
        )
    }
    
    // MARK: - Location Analysis
    
    private func performLocationAnalysis(for routeCoordinates: [LocationData]) async -> RunLocationAnalysis? {
        guard !routeCoordinates.isEmpty else {
            print("🗺️ No route coordinates provided for location analysis")
            return nil
        }
        
        print("🗺️ ========== LOCATION ANALYSIS ==========")
        print("🗺️ Analyzing route with \(routeCoordinates.count) coordinates")
        
        // Find key points: start, furthest from start, end
        let keyPoints = findKeyPointsInRoute(routeCoordinates)
        print("🗺️ Key points identified: \(keyPoints.count)")
        
        // Reverse geocode key points
        let locationDetails = await analyzeKeyPoints(keyPoints)
        print("🗺️ Geocoded \(locationDetails.count) location details")
        
        // Create smart location analysis
        let analysis = createLocationAnalysis(from: locationDetails, keyPoints: keyPoints)
        
        print("🗺️ Final analysis: \(analysis?.displayText ?? "No analysis")")
        print("🗺️ =====================================")
        
        return analysis
    }
    
    private func findKeyPointsInRoute(_ coordinates: [LocationData]) -> [LocationData] {
        guard let startCoord = coordinates.first else { return [] }
        
        var keyPoints: [LocationData] = [startCoord]
        
        // Find the furthest point from start
        let startLocation = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
        
        var furthestPoint = startCoord
        var maxDistance: Double = 0
        
        // Sample every 10th coordinate to avoid processing thousands of points
        let sampleInterval = max(1, coordinates.count / 100) // Sample ~100 points max
        
        for (index, coord) in coordinates.enumerated() {
            guard index % sampleInterval == 0 else { continue }
            
            let currentLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = startLocation.distance(from: currentLocation)
            
            if distance > maxDistance {
                maxDistance = distance
                furthestPoint = coord
            }
        }
        
        // Add furthest point if it's different from start
        if furthestPoint.latitude != startCoord.latitude || furthestPoint.longitude != startCoord.longitude {
            keyPoints.append(furthestPoint)
        }
        
        // Add end point if different from start
        if let endCoord = coordinates.last,
           (endCoord.latitude != startCoord.latitude || endCoord.longitude != startCoord.longitude) {
            keyPoints.append(endCoord)
        }
        
        print("🗺️ Key points found: start, \(keyPoints.count > 2 ? "furthest, " : "")end")
        print("🗺️ Furthest point is \(Int(maxDistance))m from start")
        
        return keyPoints
    }
    
    private func analyzeKeyPoints(_ keyPoints: [LocationData]) async -> [DetailedLocationInfo] {
        var locationDetails: [DetailedLocationInfo] = []
        
        for (index, point) in keyPoints.enumerated() {
            let pointType: LocationPointType = {
                if index == 0 { return .start }
                else if index == keyPoints.count - 1 { return .end }
                else { return .furthest }
            }()
            
            if let locationInfo = await reverseGeocodeLocation(point, pointType: pointType) {
                locationDetails.append(locationInfo)
            }
        }
        
        return locationDetails
    }
    
    private func reverseGeocodeLocation(_ locationData: LocationData, pointType: LocationPointType) async -> DetailedLocationInfo? {
        let location = CLLocation(latitude: locationData.latitude, longitude: locationData.longitude)
        let geocoder = CLGeocoder()
        
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            
            let locationInfo = DetailedLocationInfo(
                pointType: pointType,
                neighborhood: placemark.subLocality ?? placemark.thoroughfare,
                city: placemark.locality,
                subAdministrativeArea: placemark.subAdministrativeArea,
                administrativeArea: placemark.administrativeArea,
                country: placemark.country,
                coordinate: CLLocationCoordinate2D(latitude: locationData.latitude, longitude: locationData.longitude)
            )
            
            print("🗺️ \(pointType.description): \(locationInfo.debugDescription)")
            return locationInfo
        } catch {
            print("🗺️ Failed to geocode \(pointType.description): \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createLocationAnalysis(from locationDetails: [DetailedLocationInfo], keyPoints: [LocationData]) -> RunLocationAnalysis? {
        guard !locationDetails.isEmpty else {
            print("🗺️ No location details available for analysis")
            return nil
        }
        
        let cities = Set(locationDetails.compactMap { $0.bestCityName })
        let neighborhoods = Set(locationDetails.compactMap { $0.neighborhood })
        
        print("🗺️ Analysis found \(cities.count) unique cities: \(cities.joined(separator: ", "))")
        print("🗺️ Analysis found \(neighborhoods.count) unique neighborhoods: \(neighborhoods.joined(separator: ", "))")
        
        // Determine analysis type and display text
        if cities.count > 1 {
            // Multi-city run
            let cityList = Array(cities).sorted()
            let displayText = cityList.joined(separator: " → ")
            
            return RunLocationAnalysis(
                type: .multiCity,
                displayText: displayText,
                primaryCity: cityList.first,
                secondaryCity: cityList.count > 1 ? cityList[1] : nil,
                neighborhood: nil
            )
        } else if let city = cities.first {
            // Single city - check for neighborhood
            if let neighborhood = neighborhoods.first, neighborhoods.count == 1 {
                // Single neighborhood in city
                let displayText = "\(neighborhood) in \(city)"
                
                return RunLocationAnalysis(
                    type: .neighborhoodInCity,
                    displayText: displayText,
                    primaryCity: city,
                    secondaryCity: nil,
                    neighborhood: neighborhood
                )
            } else {
                // Just city name
                return RunLocationAnalysis(
                    type: .singleLocation,
                    displayText: city,
                    primaryCity: city,
                    secondaryCity: nil,
                    neighborhood: nil
                )
            }
        }
        
        return nil
    }
}