import SwiftUI
import CoreLocation

struct AnimatedRoutePathView: View {
    let coordinates: [LocationData]
    let songPositions: [SongPosition]?
    let lineWidth: CGFloat
    let showSongIndicators: Bool
    let colorScheme: RunColorScheme?
    let animationDuration: Double
    
    @State private var animationProgress: Double = 0
    @State private var isAnimating = false
    
    init(
        coordinates: [LocationData], 
        songPositions: [SongPosition]? = nil, 
        lineWidth: CGFloat = 3.0, 
        showSongIndicators: Bool = false, 
        colorScheme: RunColorScheme? = nil,
        animationDuration: Double = 3.0
    ) {
        self.coordinates = coordinates
        self.songPositions = songPositions
        self.lineWidth = lineWidth
        self.showSongIndicators = showSongIndicators
        self.colorScheme = colorScheme
        self.animationDuration = animationDuration
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Animated route that progressively reveals
                animatedRouteView(in: geometry)
                
                // Song indicators that appear after route animation
                if showSongIndicators, let songPositions = songPositions, animationProgress > 0.8 {
                    songIndicators(in: geometry)
                        .opacity(animationProgress > 0.8 ? (animationProgress - 0.8) * 5 : 0)
                        .animation(.easeInOut(duration: 0.5), value: animationProgress)
                }
                
                // Optional: Running dot that follows the route
                if isAnimating && !coordinates.isEmpty {
                    runnerDot(in: geometry)
                }
            }
        }
        .onAppear {
            startAnimation()
        }
        .onTapGesture {
            // Allow restarting animation on tap
            restartAnimation()
        }
    }
    
    private func animatedRouteView(in geometry: GeometryProxy) -> some View {
        Path { path in
            guard !coordinates.isEmpty else { return }
            
            let normalizedCoordinates = normalizeCoordinates(coordinates, in: geometry.size)
            let totalPoints = normalizedCoordinates.count
            let pointsToShow = Int(Double(totalPoints) * animationProgress)
            
            if pointsToShow > 0 {
                let visibleCoordinates = Array(normalizedCoordinates.prefix(pointsToShow))
                let animatedPath = createSketchyPath(from: visibleCoordinates)
                path.addPath(animatedPath)
            }
        }
        .stroke(
            getRouteGradient(),
            style: StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round)
        )
        .opacity(0.85)
    }
    
    private func songIndicators(in geometry: GeometryProxy) -> some View {
        Group {
            if let songPositions = songPositions {
                let indexedPositions = Array(songPositions.enumerated())
                let normalizedCoords = normalizeCoordinates(coordinates, in: geometry.size)
                
                ForEach(indexedPositions, id: \.offset) { index, songPosition in
                    if let position = getPositionForSong(songPosition, normalizedCoords: normalizedCoords) {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                            
                            if songPosition.isPowerSong {
                                Text("🔥")
                                    .font(.system(size: 14))
                            } else {
                                Text(romanNumeral(for: index + 1))
                                    .font(.custom("Helvetica Neue", size: 10))
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                            }
                        }
                        .position(x: position.x, y: position.y)
                        .scaleEffect(animationProgress > 0.9 ? 1.0 : 0.1)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: animationProgress)
                    }
                }
            }
        }
    }
    
    private func runnerDot(in geometry: GeometryProxy) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.orange, Color.red],
                    center: .center,
                    startRadius: 2,
                    endRadius: 6
                )
            )
            .frame(width: 12, height: 12)
            .position(runnerPosition(in: geometry))
            .shadow(color: .black.opacity(0.3), radius: 2)
    }
    
    private func runnerPosition(in geometry: GeometryProxy) -> CGPoint {
        guard !coordinates.isEmpty else { return CGPoint(x: 0, y: 0) }
        
        let normalizedCoordinates = normalizeCoordinates(coordinates, in: geometry.size)
        let totalPoints = normalizedCoordinates.count
        let currentIndex = Int(Double(totalPoints - 1) * animationProgress)
        
        if currentIndex < normalizedCoordinates.count {
            return normalizedCoordinates[currentIndex]
        }
        return normalizedCoordinates.last ?? CGPoint(x: 0, y: 0)
    }
    
    private func startAnimation() {
        guard !isAnimating else { return }
        
        animationProgress = 0
        isAnimating = true
        
        withAnimation(.easeInOut(duration: animationDuration)) {
            animationProgress = 1.0
        }
        
        // Stop animation flag after completion
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            isAnimating = false
        }
    }
    
    private func restartAnimation() {
        isAnimating = false
        animationProgress = 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            startAnimation()
        }
    }
    
    // MARK: - Helper Functions (copied from RoutePathView)
    
    private func normalizeCoordinates(_ coordinates: [LocationData], in size: CGSize) -> [CGPoint] {
        guard !coordinates.isEmpty else { return [] }
        
        let coords = coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        
        // Find bounds
        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!
        
        // Handle edge case where all points are the same
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        
        if latRange == 0 && lonRange == 0 {
            // Single point - center it
            return [CGPoint(x: size.width / 2, y: size.height / 2)]
        }
        
        // Add padding
        let padding: CGFloat = 20
        let availableWidth = size.width - (padding * 2)
        let availableHeight = size.height - (padding * 2)
        
        return coords.map { coord in
            let normalizedLat = latRange > 0 ? (coord.latitude - minLat) / latRange : 0.5
            let normalizedLon = lonRange > 0 ? (coord.longitude - minLon) / lonRange : 0.5
            
            // Flip latitude for screen coordinates (higher lat = lower Y)
            let x = normalizedLon * availableWidth + padding
            let y = (1.0 - normalizedLat) * availableHeight + padding
            
            return CGPoint(x: x, y: y)
        }
    }
    
    private func createSketchyPath(from points: [CGPoint]) -> Path {
        guard points.count > 1 else {
            var path = Path()
            if let point = points.first {
                path.addEllipse(in: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
            }
            return path
        }
        
        var path = Path()
        path.move(to: points[0])
        
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        
        return path
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
    
    private func getPositionForSong(_ songPosition: SongPosition, normalizedCoords: [CGPoint]) -> CGPoint? {
        guard !normalizedCoords.isEmpty else { return nil }
        
        let progress = songPosition.progressRatio
        let clampedProgress = max(0, min(1, progress))
        let index = Int(Double(normalizedCoords.count - 1) * clampedProgress)
        
        return normalizedCoords[safe: index] ?? normalizedCoords.last
    }
    
    private func romanNumeral(for number: Int) -> String {
        let romanNumerals = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
        return romanNumerals[safe: number - 1] ?? "\(number)"
    }
}


#Preview {
    let sampleCoordinates = [
        LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
        LocationData(latitude: 37.7759, longitude: -122.4184, timestamp: Date()),
        LocationData(latitude: 37.7769, longitude: -122.4174, timestamp: Date()),
        LocationData(latitude: 37.7779, longitude: -122.4164, timestamp: Date())
    ]
    
    AnimatedRoutePathView(
        coordinates: sampleCoordinates,
        lineWidth: 4.0,
        animationDuration: 2.0
    )
    .frame(width: 200, height: 200)
    .background(Color.gray.opacity(0.2))
}