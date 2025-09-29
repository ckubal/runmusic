import Foundation

struct StravaActivity: Codable {
    let id: Int
    let name: String
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let totalElevationGain: Double
    let type: String
    let startDate: String
    let startDateLocal: String
    let timezone: String
    let startLatlng: [Double]?
    let endLatlng: [Double]?
    let map: StravaMap?
    let averageSpeed: Double
    let maxSpeed: Double
    
    private enum CodingKeys: String, CodingKey {
        case id, name, distance, type, timezone, map
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case startDate = "start_date"
        case startDateLocal = "start_date_local"
        case startLatlng = "start_latlng"
        case endLatlng = "end_latlng"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
    }
}

struct StravaMap: Codable {
    let id: String
    let polyline: String?
    let summaryPolyline: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, polyline
        case summaryPolyline = "summary_polyline"
    }
}

struct StravaDetailedActivity: Codable {
    let id: Int
    let name: String
    let distance: Double
    let movingTime: Int
    let elapsedTime: Int
    let totalElevationGain: Double
    let type: String
    let startDate: String
    let startDateLocal: String
    let timezone: String
    let startLatlng: [Double]?
    let endLatlng: [Double]?
    let map: StravaMap?
    let averageSpeed: Double
    let maxSpeed: Double
    let locationCity: String?
    let locationState: String?
    let locationCountry: String?
    let utcOffset: Double?
    
    private enum CodingKeys: String, CodingKey {
        case id, name, distance, type, timezone, map
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case startDate = "start_date"
        case startDateLocal = "start_date_local"
        case startLatlng = "start_latlng"
        case endLatlng = "end_latlng"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case locationCity = "location_city"
        case locationState = "location_state"
        case locationCountry = "location_country"
        case utcOffset = "utc_offset"
    }
}

struct StravaStream: Codable {
    let type: String
    let data: [StreamData]
    let seriesType: String
    let originalSize: Int
    let resolution: String
    
    private enum CodingKeys: String, CodingKey {
        case type, data, resolution
        case seriesType = "series_type"
        case originalSize = "original_size"
    }
}

enum StreamData: Codable {
    case coordinate([Double])
    case double(Double)
    case int(Int)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let coordinateArray = try? container.decode([Double].self), coordinateArray.count == 2 {
            self = .coordinate(coordinateArray)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else {
            throw DecodingError.typeMismatch(StreamData.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to decode StreamData"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .coordinate(let array):
            try container.encode(array)
        case .double(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
}

struct StravaAuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int
    let athlete: StravaAthlete
    
    private enum CodingKeys: String, CodingKey {
        case athlete
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

struct StravaAthlete: Codable {
    let id: Int
    let firstname: String?
    let lastname: String?
    let profileMedium: String?
    let profile: String?
    let city: String?
    let state: String?
    let country: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, firstname, lastname, city, state, country
        case profileMedium = "profile_medium"
        case profile
    }
}

// Separate model for token refresh response (no athlete field)
struct StravaTokenRefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int
    
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}