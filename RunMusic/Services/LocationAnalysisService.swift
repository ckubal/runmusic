import Foundation
import CoreLocation
import MapKit

struct LocationAnalysisService {
    static let shared = LocationAnalysisService()
    
    // Geocoding cache to avoid repeated requests for nearby locations
    private static var geocodingCache: [String: DetailedLocationInfo] = [:]
    private static var lastGeocodingRequest: Date = Date.distantPast
    private static let minGeocodingInterval: TimeInterval = 1.2 // 1.2 seconds between requests
    private static let geocodingCacheRadius: Double = 500 // meters - cache hits within this radius
    
    private init() {}
    
    // MARK: - Main Analysis Function
    
    func analyzeRunLocation(for routeCoordinates: [LocationData]) async -> RunLocationAnalysis? {
        guard !routeCoordinates.isEmpty else {
            print("🗺️ No route coordinates provided for location analysis")
            return nil
        }
        
        print("🗺️ ========== LOCATION ANALYSIS ==========")
        print("🗺️ Analyzing route with \(routeCoordinates.count) coordinates")
        
        let keyPoints = findKeyPointsInRoute(routeCoordinates)
        print("🗺️ Key points: start, \(keyPoints.count - 2) intermediate, end")
        
        let locationDetails = await analyzeKeyPoints(keyPoints)
        print("🗺️ Geocoded \(locationDetails.count) location details")
        
        let analysis = createLocationAnalysis(from: locationDetails, keyPoints: keyPoints)
        
        print("🗺️ Final analysis:")
        print("🗺️   Display text: '\(analysis?.displayText ?? "No analysis")'")
        print("🗺️   Type: \(analysis?.type ?? .singleLocation)")
        print("🗺️   Primary city: '\(analysis?.primaryCity ?? "nil")'")
        print("🗺️   Neighborhood: '\(analysis?.neighborhood ?? "nil")'")
        print("🗺️ =====================================")
        
        return analysis
    }
    
    // MARK: - Route Analysis
    
    private func findKeyPointsInRoute(_ coordinates: [LocationData]) -> [LocationData] {
        guard let startCoord = coordinates.first else { return [] }
        
        var keyPoints: [LocationData] = [startCoord]
        
        // Find the furthest point from start
        let startLocation = CLLocation(latitude: startCoord.latitude, longitude: startCoord.longitude)
        
        var furthestPoint = startCoord
        var maxDistance: Double = 0
        
        // Sample every 10th coordinate to avoid processing thousands of points
        let sampleInterval = max(1, coordinates.count / 100) // Sample ~100 points max
        
        for i in stride(from: 0, to: coordinates.count, by: sampleInterval) {
            let coord = coordinates[i]
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let distance = startLocation.distance(from: location)
            
            if distance > maxDistance {
                maxDistance = distance
                furthestPoint = coord
            }
        }
        
        print("🗺️ Furthest point is \(Int(maxDistance))m from start")
        
        // Add furthest point if it's significantly far from start (>500m)
        if maxDistance > 500 {
            keyPoints.append(furthestPoint)
        }
        
        // Add multiple sampling points for better neighborhood diversity
        if coordinates.count > 100 {
            // Add quarter point, mid point, and three-quarter point for better coverage
            let quarterIndex = coordinates.count / 4
            let midIndex = coordinates.count / 2
            let threeQuarterIndex = (coordinates.count * 3) / 4
            
            keyPoints.append(coordinates[quarterIndex])
            keyPoints.append(coordinates[midIndex])
            keyPoints.append(coordinates[threeQuarterIndex])
        } else if coordinates.count > 50 {
            // For shorter routes, just add midpoint
            let midIndex = coordinates.count / 2
            keyPoints.append(coordinates[midIndex])
        }
        
        // Add end point if different from start (for out-and-back vs loops)
        if let endCoord = coordinates.last {
            let endLocation = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
            let startToEndDistance = startLocation.distance(from: endLocation)
            
            if startToEndDistance > 100 { // More than 100m from start
                keyPoints.append(endCoord)
            }
        }
        
        return keyPoints
    }
    
    // MARK: - Reverse Geocoding
    
    private func analyzeKeyPoints(_ keyPoints: [LocationData]) async -> [DetailedLocationInfo] {
        var locationDetails: [DetailedLocationInfo] = []
        
        // Limit to 2 key points maximum to reduce API calls
        let limitedKeyPoints = Array(keyPoints.prefix(2))
        print("🗺️ Limited key points to \(limitedKeyPoints.count) to avoid rate limiting")
        
        for (index, point) in limitedKeyPoints.enumerated() {
            let pointType: LocationPointType = {
                switch index {
                case 0: return .start
                default: return .end
                }
            }()
            
            if let details = await reverseGeocodeWithCache(
                latitude: point.latitude,
                longitude: point.longitude,
                pointType: pointType
            ) {
                locationDetails.append(details)
            }
        }
        
        return locationDetails
    }
    
    // MARK: - Cached Reverse Geocoding
    
    private func reverseGeocodeWithCache(
        latitude: Double,
        longitude: Double,
        pointType: LocationPointType
    ) async -> DetailedLocationInfo? {
        let cacheKey = generateCacheKey(latitude: latitude, longitude: longitude)
        
        // Check cache for nearby location
        if let cachedResult = Self.geocodingCache[cacheKey] {
            print("🗺️ Cache hit for \(pointType) at (\(latitude), \(longitude))")
            return DetailedLocationInfo(
                pointType: pointType,
                neighborhood: cachedResult.neighborhood,
                city: cachedResult.city,
                subAdministrativeArea: cachedResult.subAdministrativeArea,
                administrativeArea: cachedResult.administrativeArea,
                country: cachedResult.country,
                coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            )
        }
        
        // Check if we need to wait for rate limiting
        let timeSinceLastRequest = Date().timeIntervalSince(Self.lastGeocodingRequest)
        if timeSinceLastRequest < Self.minGeocodingInterval {
            let waitTime = Self.minGeocodingInterval - timeSinceLastRequest
            print("🗺️ Rate limiting: waiting \(String(format: "%.1f", waitTime))s before geocoding \(pointType)")
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        
        Self.lastGeocodingRequest = Date()
        
        // Perform geocoding
        let result = await reverseGeocodeEnhanced(
            latitude: latitude,
            longitude: longitude,
            pointType: pointType
        )
        
        // Cache the result if successful
        if let result = result {
            Self.geocodingCache[cacheKey] = result
            print("🗺️ Cached result for (\(latitude), \(longitude))")
        }
        
        return result
    }
    
    private func generateCacheKey(latitude: Double, longitude: Double) -> String {
        // Round to ~100m precision for cache clustering
        let roundedLat = round(latitude * 1000) / 1000
        let roundedLon = round(longitude * 1000) / 1000
        return "\(roundedLat),\(roundedLon)"
    }
    
    // MARK: - Cache Management
    
    static func clearGeocodingCache() {
        geocodingCache.removeAll()
        print("🗺️ Cleared geocoding cache")
    }
    
    static func getCacheStats() -> (count: Int, memorySize: Int) {
        let count = geocodingCache.count
        let estimatedSize = count * 200 // rough estimate in bytes
        return (count, estimatedSize)
    }
    
    private func reverseGeocodeEnhanced(
        latitude: Double,
        longitude: Double,
        pointType: LocationPointType
    ) async -> DetailedLocationInfo? {
        return await withCheckedContinuation { continuation in
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let geocoder = CLGeocoder()
            
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    print("🌍 Reverse geocoding failed for \(pointType): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    print("🌍 No placemark found for \(pointType)")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Better neighborhood extraction - prioritize actual neighborhood names over street names
                let neighborhood = placemark.subLocality ?? 
                                 placemark.areasOfInterest?.first ??
                                 (placemark.thoroughfare?.contains("Street") == false && 
                                  placemark.thoroughfare?.contains("Avenue") == false &&
                                  placemark.thoroughfare?.contains("Road") == false &&
                                  placemark.thoroughfare?.contains("Highway") == false &&
                                  placemark.thoroughfare?.contains("Boulevard") == false &&
                                  placemark.thoroughfare?.contains("Drive") == false ? placemark.thoroughfare : nil)
                
                let details = DetailedLocationInfo(
                    pointType: pointType,
                    neighborhood: neighborhood,
                    city: placemark.locality,
                    subAdministrativeArea: placemark.subAdministrativeArea,
                    administrativeArea: placemark.administrativeArea,
                    country: placemark.country,
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                )
                
                print("🌍 \(pointType): \(details.debugDescription)")
                continuation.resume(returning: details)
            }
        }
    }
    
    // MARK: - Analysis Logic
    
    private func createLocationAnalysis(
        from locationDetails: [DetailedLocationInfo],
        keyPoints: [LocationData]
    ) -> RunLocationAnalysis? {
        guard !locationDetails.isEmpty else { return nil }
        
        // Group locations by city
        let cities = Set(locationDetails.compactMap { $0.bestCityName })
        let neighborhoods = Set(locationDetails.compactMap { $0.neighborhood })
        
        print("🗺️ Analysis Debug:")
        print("🗺️   Cities found: \(cities)")
        print("🗺️   Raw neighborhoods: \(neighborhoods)")
        
        for detail in locationDetails {
            print("🗺️   \(detail.pointType): neighborhood='\(detail.neighborhood ?? "nil")', city='\(detail.bestCityName ?? "nil")'")
        }
        
        let analysis: RunLocationAnalysis
        
        if cities.count > 1 {
            // Multi-city run
            analysis = createMultiCityAnalysis(locationDetails, cities: Array(cities))
        } else if let primaryCity = cities.first {
            // Single city run
            analysis = createSingleCityAnalysis(locationDetails, city: primaryCity, neighborhoods: neighborhoods)
        } else {
            // Fallback - no clear city
            analysis = RunLocationAnalysis(
                type: .singleLocation,
                displayText: "Unknown Location",
                primaryCity: nil,
                secondaryCity: nil,
                neighborhood: nil
            )
        }
        
        return analysis
    }
    
    private func createMultiCityAnalysis(
        _ locationDetails: [DetailedLocationInfo],
        cities: [String]
    ) -> RunLocationAnalysis {
        // Find start and end cities
        let startCity = locationDetails.first?.bestCityName
        let endCity = locationDetails.last?.bestCityName
        
        let displayText: String
        let type: RunLocationType
        
        if cities.count == 2, let start = startCity, let end = endCity, start != end {
            // Clean city-to-city run
            displayText = "\(start) → \(end)"
            type = .multiCity
        } else {
            // Complex multi-city (3+ cities) - show actual city names
            let sortedCities = cities.sorted()
            if sortedCities.count <= 4 {
                // Show up to 4 cities with arrows
                displayText = sortedCities.joined(separator: " → ")
            } else {
                // Too many cities - show first, last, and count
                displayText = "\(sortedCities.first ?? "Start") → \(sortedCities.last ?? "End") (+\(sortedCities.count - 2) cities)"
            }
            type = .multiCity
        }
        
        return RunLocationAnalysis(
            type: type,
            displayText: displayText,
            primaryCity: startCity,
            secondaryCity: endCity,
            neighborhood: nil
        )
    }
    
    private func createSingleCityAnalysis(
        _ locationDetails: [DetailedLocationInfo],
        city: String,
        neighborhoods: Set<String>
    ) -> RunLocationAnalysis {
        // Check if we explored interesting neighborhoods - be less aggressive with filtering
        let validNeighborhoods = neighborhoods.filter { neighborhood in
            // Only filter out obvious street addresses and very short names
            let isStreetAddress = (neighborhood.contains(" Street") || 
                                 neighborhood.contains(" Avenue") || 
                                 neighborhood.contains(" Road") || 
                                 neighborhood.contains(" Highway") ||
                                 neighborhood.contains(" Boulevard") ||
                                 neighborhood.contains(" Drive")) &&
                                 (neighborhood.split(separator: " ").count <= 3) // Allow longer descriptive names
            
            return !isStreetAddress && 
                   neighborhood.count > 2 &&
                   !neighborhood.lowercased().hasPrefix("county") &&
                   !neighborhood.lowercased().contains("zip code")
        }
        
        print("🗺️   Valid neighborhoods after filtering: \(validNeighborhoods)")
        
        let displayText: String
        let type: RunLocationType
        let primaryNeighborhood: String?
        
        if validNeighborhoods.count >= 2 {
            // Multiple neighborhoods - show the most interesting one (usually furthest point)
            let furthestPoint = locationDetails.first { $0.pointType == .furthest }
            primaryNeighborhood = furthestPoint?.neighborhood ?? validNeighborhoods.first
            
            if let neighborhood = primaryNeighborhood {
                displayText = "\(neighborhood) in \(city)"
                type = .neighborhoodInCity
            } else {
                displayText = city
                type = .singleLocation
            }
        } else if let neighborhood = validNeighborhoods.first {
            // Single interesting neighborhood
            displayText = "\(neighborhood) in \(city)"
            primaryNeighborhood = neighborhood
            type = .neighborhoodInCity
        } else {
            // Just the city
            displayText = city
            primaryNeighborhood = nil
            type = .singleLocation
        }
        
        return RunLocationAnalysis(
            type: type,
            displayText: displayText,
            primaryCity: city,
            secondaryCity: nil,
            neighborhood: primaryNeighborhood
        )
    }
}