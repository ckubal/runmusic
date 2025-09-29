import Foundation
import CoreLocation

class WeatherService {
    static let shared = WeatherService()
    
    private init() {}
    
    // Visual Crossing Weather API (1000 records/day free, then $0.0001/record)
    private let apiKey = "G6HXN5XKWH29FCVA5ASLPNZC0"
    private let baseURL = "https://weather.visualcrossing.com/VisualCrossingWebServices/rest/services/timeline"
    
    /// Fetch weather data for a specific location and time using Visual Crossing API
    /// - Parameters:
    ///   - location: CLLocationCoordinate2D of the run location
    ///   - date: Date of the run (for historical weather data)
    /// - Returns: WeatherData if successful
    func fetchWeatherData(for location: CLLocationCoordinate2D, on date: Date) async throws -> WeatherData {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        
        // Visual Crossing Timeline API URL for historical weather
        // Format: /timeline/{location}/{date}?key={key}&include=hours&elements=temp,humidity,windspeed,conditions
        let urlString = "\(baseURL)/\(location.latitude),\(location.longitude)/\(dateString)?key=\(apiKey)&include=hours&elements=temp,humidity,windspeed,conditions&unitGroup=us"
        
        guard let url = URL(string: urlString) else {
            throw WeatherError.invalidResponse
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            print("❌ Visual Crossing API error: \(statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("❌ Error response: \(errorData)")
            }
            throw WeatherError.invalidResponse
        }
        
        let weatherResponse = try JSONDecoder().decode(VisualCrossingResponse.self, from: data)
        
        // Find the hour closest to the run time
        let calendar = Calendar.current
        let runHour = calendar.component(.hour, from: date)
        
        let dayData = weatherResponse.days.first
        let hourData = dayData?.hours?.first { hour in
            let hourNumber = Int(hour.datetime.prefix(2)) ?? 0
            return abs(hourNumber - runHour) <= 1 // Within 1 hour
        } ?? dayData?.hours?.first // Fallback to first hour if no close match
        
        // Use hourly data if available, otherwise use daily data
        let temperature = hourData?.temp ?? dayData?.temp ?? 70.0
        let humidity = hourData?.humidity ?? dayData?.humidity ?? 50.0
        let windSpeed = hourData?.windspeed ?? dayData?.windspeed ?? 5.0
        let conditions = hourData?.conditions ?? dayData?.conditions ?? "clear"
        
        return WeatherData(
            temperature: temperature,
            condition: mapVisualCrossingCondition(from: conditions),
            windSpeed: windSpeed,
            humidity: humidity,
            timeOfDay: determineTimeOfDay(from: date),
            description: conditions.capitalized,
            dataSource: .api
        )
    }
    
    /// For demo purposes - simulate weather based on location and date
    /// This can be used when API quota is exhausted or for testing
    func simulateWeatherData(for location: CLLocationCoordinate2D, on date: Date) -> WeatherData {
        // More realistic simulation based on location, season, and time
        let calendar = Calendar.current
        let month = calendar.component(.month, from: date)
        let hour = calendar.component(.hour, from: date)
        let day = calendar.component(.day, from: date)
        
        // Base temperature by season (for temperate climate around 40°N)
        let baseTemp: Double
        switch month {
        case 12, 1, 2: baseTemp = 35 // Winter
        case 3, 4, 5: baseTemp = 55  // Spring
        case 6, 7, 8: baseTemp = 75  // Summer
        case 9, 10, 11: baseTemp = 60 // Fall
        default: baseTemp = 60
        }
        
        // Adjust for latitude (warmer in south, colder in north)
        let latitudeAdjustment = (40 - location.latitude) * 1.5
        
        // Time of day adjustment (cooler at night/morning)
        let timeAdjustment: Double
        switch hour {
        case 0..<6: timeAdjustment = -10  // Night
        case 6..<9: timeAdjustment = -5   // Early morning
        case 9..<12: timeAdjustment = 0   // Morning
        case 12..<15: timeAdjustment = 5  // Afternoon peak
        case 15..<18: timeAdjustment = 3  // Late afternoon
        case 18..<21: timeAdjustment = -2 // Evening
        default: timeAdjustment = -7      // Night
        }
        
        // Daily variation (deterministic based on date)
        let dateHash = "\(date.timeIntervalSince1970)".hashValue
        let dailyVariation = Double(abs(dateHash) % 10) - 5 // -5 to +5 variation
        
        let temperature = baseTemp + latitudeAdjustment + timeAdjustment + dailyVariation
        
        // Determine weather condition based on temperature and deterministic factors
        let condition: WeatherData.WeatherCondition
        let conditionSeed = (day + month + Int(location.latitude * 100)) % 100
        
        if temperature < 32 && conditionSeed < 30 {
            // Only snow when it's actually cold enough
            condition = .snow
        } else if temperature < 45 && conditionSeed < 20 {
            // More likely to be cloudy/rainy when cooler
            condition = .rain
        } else if conditionSeed < 15 {
            condition = .rain
        } else if conditionSeed < 35 {
            condition = .cloudy
        } else if conditionSeed < 40 && hour >= 6 && hour <= 9 {
            condition = .fog // Morning fog
        } else if conditionSeed < 5 && month >= 6 && month <= 8 {
            condition = .thunderstorm // Summer storms
        } else {
            condition = .clear
        }
        
        // Deterministic wind and humidity based on location and date
        let windSeed = abs("\(date)-\(location.latitude)".hashValue)
        let windSpeed = Double(windSeed % 20) + Double(windSeed % 10) / 10.0 // 0-20 mph
        
        let humiditySeed = abs("\(date)-\(location.longitude)".hashValue)
        let humidity = Double(humiditySeed % 40) + 40 // 40-80%
        
        return WeatherData(
            temperature: temperature,
            condition: condition,
            windSpeed: windSpeed,
            humidity: humidity,
            timeOfDay: determineTimeOfDay(from: date),
            description: condition.rawValue.capitalized,
            dataSource: .simulated
        )
    }
    
    private func mapVisualCrossingCondition(from conditions: String) -> WeatherData.WeatherCondition {
        let lowercased = conditions.lowercased()
        switch lowercased {
        case let condition where condition.contains("clear"):
            return .clear
        case let condition where condition.contains("cloud") || condition.contains("overcast"):
            return .cloudy
        case let condition where condition.contains("rain") || condition.contains("drizzle") || condition.contains("showers"):
            return .rain
        case let condition where condition.contains("snow") || condition.contains("blizzard"):
            return .snow
        case let condition where condition.contains("fog") || condition.contains("mist"):
            return .fog
        case let condition where condition.contains("thunder") || condition.contains("storm"):
            return .thunderstorm
        default:
            return .clear // Default to clear for unknown conditions
        }
    }
    
    private func determineTimeOfDay(from date: Date) -> WeatherData.TimeOfDay {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        switch hour {
        case 5..<7: return .dawn
        case 7..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<21: return .evening
        default: return .night
        }
    }
}

// MARK: - Visual Crossing API Response Models

private struct VisualCrossingResponse: Codable {
    let days: [DayData]
    
    struct DayData: Codable {
        let datetime: String
        let temp: Double?
        let humidity: Double?
        let windspeed: Double?
        let conditions: String?
        let hours: [HourData]?
    }
    
    struct HourData: Codable {
        let datetime: String // Format: "HH:mm:ss"
        let temp: Double?
        let humidity: Double?
        let windspeed: Double?
        let conditions: String?
    }
}

// MARK: - Errors

enum WeatherError: Error {
    case invalidResponse
    case apiKeyMissing
    case networkError(Error)
    
    var localizedDescription: String {
        switch self {
        case .invalidResponse:
            return "Invalid weather API response"
        case .apiKeyMissing:
            return "Weather API key not configured"
        case .networkError(let error):
            return "Weather network error: \(error.localizedDescription)"
        }
    }
}