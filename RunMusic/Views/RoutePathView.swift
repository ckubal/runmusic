import SwiftUI
import CoreLocation

struct RoutePathView: View {
    let coordinates: [LocationData]
    let songPositions: [SongPosition]?
    let lineWidth: CGFloat
    let showSongIndicators: Bool
    let colorScheme: RunColorScheme?
    
    init(coordinates: [LocationData], songPositions: [SongPosition]? = nil, lineWidth: CGFloat = 3.0, showSongIndicators: Bool = false, colorScheme: RunColorScheme? = nil) {
        self.coordinates = coordinates
        self.songPositions = songPositions
        self.lineWidth = lineWidth
        self.showSongIndicators = showSongIndicators
        self.colorScheme = colorScheme
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    print("🗺️ RoutePathView: Rendering \(coordinates.count) coordinates")
                    guard !coordinates.isEmpty else { 
                        print("⚠️ RoutePathView: No coordinates to render")
                        return 
                    }
                    
                    let normalizedCoordinates = normalizeCoordinates(coordinates, in: geometry.size)
                    print("🗺️ RoutePathView: Normalized to \(normalizedCoordinates.count) points")
                    let sketchyPath = createSketchyPath(from: normalizedCoordinates)
                    path.addPath(sketchyPath)
                }
                .stroke(
                    getRouteGradient(),
                    style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round)
                )
                .opacity(0.85)
                
                if showSongIndicators, let songPositions = songPositions {
                    let indexedPositions = Array(songPositions.enumerated())
                    let normalizedCoords = normalizeCoordinates(coordinates, in: geometry.size)
                    
                    ForEach(indexedPositions, id: \.offset) { index, songPosition in
                        if let position = getPositionForSong(songPosition, normalizedCoords: normalizedCoords) {
                            ZStack {
                                if songPosition.isPowerSong {
                                    // Fire emoji for Power Song - no circle background needed
                                    Text("🔥")
                                        .font(.system(size: 14)) // Larger for fire emoji
                                        .scaleEffect(1.1)
                                        .shadow(color: .orange.opacity(0.4), radius: 2, x: 0, y: 1)
                                } else {
                                    // Regular Roman numeral with circle background for other songs
                                    Circle()
                                        .fill(Color.white.opacity(0.85)) // More opaque for readability
                                        .frame(width: 12, height: 12) // Keep size
                                        .shadow(radius: 0.5)
                                    
                                    Text(romanNumeral(for: index + 1).lowercased())
                                        .font(.system(size: 6, weight: .semibold)) // Slightly bolder
                                        .foregroundColor(colorScheme?.primaryColor.color ?? .orange) // Use scheme color
                                }
                            }
                            .position(position)
                        }
                    }
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func createSketchyPath(from points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1 else { return path }
        
        // Simplify path by reducing points for smoother curves
        let simplifiedPoints = simplifyPath(points)
        guard simplifiedPoints.count > 1 else { return path }
        
        // Add slight randomness for hand-drawn effect
        let jitterAmount: CGFloat = lineWidth * 0.4
        
        // Start the path with slight jitter
        let startPoint = addJitter(to: simplifiedPoints[0], amount: jitterAmount * 0.5)
        path.move(to: startPoint)
        
        // Create smooth curves using cubic Bezier curves for more organic feel
        if simplifiedPoints.count == 2 {
            // Simple case: just two points
            let endPoint = addJitter(to: simplifiedPoints[1], amount: jitterAmount * 0.5)
            path.addLine(to: endPoint)
        } else {
            // Multiple points: create smooth curves
            for i in 1..<simplifiedPoints.count {
                let current = addJitter(to: simplifiedPoints[i], amount: jitterAmount * 0.5)
                
                if i == 1 {
                    // First segment - use quadratic curve
                    let midPoint = CGPoint(
                        x: (startPoint.x + current.x) / 2,
                        y: (startPoint.y + current.y) / 2
                    )
                    let controlPoint = addJitter(to: midPoint, amount: jitterAmount)
                    path.addQuadCurve(to: current, control: controlPoint)
                } else if i == simplifiedPoints.count - 1 {
                    // Last segment - use quadratic curve
                    let previous = path.currentPoint ?? simplifiedPoints[i-1]
                    let midPoint = CGPoint(
                        x: (previous.x + current.x) / 2,
                        y: (previous.y + current.y) / 2
                    )
                    let controlPoint = addJitter(to: midPoint, amount: jitterAmount)
                    path.addQuadCurve(to: current, control: controlPoint)
                } else {
                    // Middle segments - use cubic curves for smoothness
                    let previous = path.currentPoint ?? simplifiedPoints[i-1]
                    let next = simplifiedPoints[min(i + 1, simplifiedPoints.count - 1)]
                    
                    let control1 = CGPoint(
                        x: previous.x + (current.x - previous.x) * 0.3,
                        y: previous.y + (current.y - previous.y) * 0.3
                    )
                    let control2 = CGPoint(
                        x: current.x - (next.x - current.x) * 0.3,
                        y: current.y - (next.y - current.y) * 0.3
                    )
                    
                    path.addCurve(
                        to: current,
                        control1: addJitter(to: control1, amount: jitterAmount * 0.7),
                        control2: addJitter(to: control2, amount: jitterAmount * 0.7)
                    )
                }
            }
        }
        
        return path
    }
    
    private func simplifyPath(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 3 else { return points }
        
        var simplified: [CGPoint] = [points[0]]
        let tolerance: CGFloat = 8.0 // Minimum distance between points
        
        for i in 1..<points.count {
            let lastPoint = simplified.last!
            let currentPoint = points[i]
            let distance = sqrt(pow(currentPoint.x - lastPoint.x, 2) + pow(currentPoint.y - lastPoint.y, 2))
            
            // Only keep points that are far enough apart or are the last point
            if distance > tolerance || i == points.count - 1 {
                simplified.append(currentPoint)
            }
        }
        
        return simplified
    }
    
    private func getRouteGradient() -> LinearGradient {
        if let routeGradient = colorScheme?.routeGradient {
            return routeGradient
        } else {
            let defaultColors = [
                Color.orange.opacity(0.7),
                Color.orange.opacity(0.9),
                Color.pink.opacity(0.5)
            ]
            return LinearGradient(
                colors: defaultColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private func addJitter(to point: CGPoint, amount: CGFloat) -> CGPoint {
        return CGPoint(
            x: point.x + CGFloat.random(in: -amount...amount),
            y: point.y + CGFloat.random(in: -amount...amount)
        )
    }
    
    private func normalizeCoordinates(_ coordinates: [LocationData], in size: CGSize) -> [CGPoint] {
        guard !coordinates.isEmpty else { return [] }
        
        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            return []
        }
        
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        
        let padding: CGFloat = 20
        let availableWidth = size.width - (padding * 2)
        let availableHeight = size.height - (padding * 2)
        
        return coordinates.map { coord in
            let normalizedLat = latRange > 0 ? (coord.latitude - minLat) / latRange : 0.5
            let normalizedLon = lonRange > 0 ? (coord.longitude - minLon) / lonRange : 0.5
            
            let x = padding + (normalizedLon * availableWidth)
            let y = padding + ((1.0 - normalizedLat) * availableHeight)
            
            return CGPoint(x: x, y: y)
        }
    }
    
    private func getPositionForSong(_ songPosition: SongPosition, normalizedCoords: [CGPoint]) -> CGPoint? {
        let totalCoords = normalizedCoords.count
        guard totalCoords > 0 else { return nil }
        
        let index = Int(songPosition.progressRatio * Double(totalCoords - 1))
        let clampedIndex = min(index, totalCoords - 1)
        
        return normalizedCoords[clampedIndex]
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

struct SongPosition {
    let songIndex: Int
    let progressRatio: Double
    let isPowerSong: Bool
    
    init(songIndex: Int, progressRatio: Double, isPowerSong: Bool = false) {
        self.songIndex = songIndex
        self.progressRatio = progressRatio
        self.isPowerSong = isPowerSong
    }
}

struct RoutePathView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleCoordinates = [
            LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
            LocationData(latitude: 37.7949, longitude: -122.3994, timestamp: Date()),
            LocationData(latitude: 37.8049, longitude: -122.3894, timestamp: Date()),
            LocationData(latitude: 37.8149, longitude: -122.3794, timestamp: Date())
        ]
        
        let sampleSongPositions = [
            SongPosition(songIndex: 0, progressRatio: 0.2),
            SongPosition(songIndex: 1, progressRatio: 0.5),
            SongPosition(songIndex: 2, progressRatio: 0.8)
        ]
        
        VStack {
            RoutePathView(coordinates: sampleCoordinates)
                .frame(width: 200, height: 200)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            
            RoutePathView(
                coordinates: sampleCoordinates,
                songPositions: sampleSongPositions,
                lineWidth: 4,
                showSongIndicators: true
            )
            .frame(width: 200, height: 200)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
    }
}