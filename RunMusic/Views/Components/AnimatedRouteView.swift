import SwiftUI

// MARK: - Animated Route Drawing View

struct AnimatedRouteView: View {
    let coordinates: [LocationData]
    let songPositions: [SongPosition]
    let lineWidth: CGFloat
    let showSongIndicators: Bool
    let colorScheme: RunColorScheme
    let shouldAnimate: Bool
    let animationDuration: Double
    
    @State private var animationProgress: CGFloat = 0
    @State private var showSongMarkers = false
    
    init(
        coordinates: [LocationData],
        songPositions: [SongPosition] = [],
        lineWidth: CGFloat = 4,
        showSongIndicators: Bool = false,
        colorScheme: RunColorScheme,
        shouldAnimate: Bool = false,
        animationDuration: Double = 2.0
    ) {
        self.coordinates = coordinates
        self.songPositions = songPositions
        self.lineWidth = lineWidth
        self.showSongIndicators = showSongIndicators
        self.colorScheme = colorScheme
        self.shouldAnimate = shouldAnimate
        self.animationDuration = animationDuration
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background route path (static, lighter)
                if shouldAnimate {
                    routePath(geometry: geometry)
                        .stroke(
                            colorScheme.primaryColor.color.opacity(0.2),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                        )
                }
                
                // Animated route path
                routePath(geometry: geometry)
                    .trim(from: 0, to: shouldAnimate ? animationProgress : 1.0)
                    .stroke(
                        LinearGradient(
                            colors: [colorScheme.primaryColor.color, colorScheme.secondaryColor.color],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                    .animation(.easeInOut(duration: animationDuration), value: animationProgress)
                
                // Running dot at the end of animated path
                if shouldAnimate && animationProgress > 0 {
                    runnerDot(geometry: geometry)
                        .animation(.easeInOut(duration: 0.3), value: animationProgress)
                }
                
                // Song position indicators
                if showSongIndicators && showSongMarkers {
                    ForEach(Array(songPositions.enumerated()), id: \.offset) { index, position in
                        songMarker(geometry: geometry, position: position, index: index)
                            .opacity(shouldAnimate ? (animationProgress >= CGFloat(position.progressRatio) ? 1 : 0) : 1)
                            .scaleEffect(shouldAnimate ? (animationProgress >= CGFloat(position.progressRatio) ? 1 : 0) : 1)
                            .animation(.interpolatingSpring(stiffness: 400, damping: 15).delay(Double(index) * 0.1), value: showSongMarkers)
                    }
                }
            }
        }
        .onAppear {
            if shouldAnimate {
                // Start route animation
                withAnimation(.easeInOut(duration: animationDuration)) {
                    animationProgress = 1.0
                }
                
                // Show song markers after route is mostly drawn
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * 0.7) {
                    showSongMarkers = true
                }
            } else {
                // Static route - show everything immediately
                animationProgress = 1.0
                showSongMarkers = true
            }
        }
    }
    
    private func routePath(geometry: GeometryProxy) -> Path {
        guard !coordinates.isEmpty else { return Path() }
        
        // Convert coordinates to points
        let points = convertCoordinatesToPoints(coordinates, in: geometry)
        
        var path = Path()
        if let firstPoint = points.first {
            path.move(to: firstPoint)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
        
        return path
    }
    
    private func runnerDot(geometry: GeometryProxy) -> some View {
        let points = convertCoordinatesToPoints(coordinates, in: geometry)
        let currentIndex = Int(animationProgress * CGFloat(points.count - 1))
        let safeIndex = min(currentIndex, points.count - 1)
        
        return Circle()
            .fill(colorScheme.primaryColor.color)
            .frame(width: lineWidth * 2, height: lineWidth * 2)
            .shadow(color: colorScheme.primaryColor.color.opacity(0.6), radius: 4)
            .position(points[safeIndex])
            .scaleEffect(1.0 + sin(Date().timeIntervalSinceReferenceDate * 4) * 0.2)
            .animation(.easeInOut(duration: 0.5).repeatForever(), value: animationProgress)
    }
    
    private func songMarker(geometry: GeometryProxy, position: SongPosition, index: Int) -> some View {
        let points = convertCoordinatesToPoints(coordinates, in: geometry)
        let pointIndex = Int(position.progressRatio * Double(points.count - 1))
        let safeIndex = min(pointIndex, points.count - 1)
        
        return ZStack {
            // Pulsing background
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 16, height: 16)
                .scaleEffect(1.0 + sin(Date().timeIntervalSinceReferenceDate * 2 + Double(index)) * 0.1)
            
            // Music note icon
            Image(systemName: "music.note")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(colorScheme.primaryColor.color)
        }
        .position(points[safeIndex])
        .animation(.easeInOut(duration: 1.0).repeatForever(), value: UUID())
    }
    
    private func convertCoordinatesToPoints(_ coordinates: [LocationData], in geometry: GeometryProxy) -> [CGPoint] {
        guard !coordinates.isEmpty else { return [] }
        
        // Find bounds
        let latitudes = coordinates.map { $0.latitude }
        let longitudes = coordinates.map { $0.longitude }
        
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        
        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        
        // Prevent division by zero
        let safeLatRange = latRange > 0 ? latRange : 1
        let safeLonRange = lonRange > 0 ? lonRange : 1
        
        // Convert to points with padding
        let padding: CGFloat = 20
        let width = geometry.size.width - (2 * padding)
        let height = geometry.size.height - (2 * padding)
        
        return coordinates.map { coord in
            let x = padding + ((coord.longitude - minLon) / safeLonRange) * width
            let y = padding + (1 - (coord.latitude - minLat) / safeLatRange) * height // Flip Y axis
            return CGPoint(x: x, y: y)
        }
    }
}

// MARK: - Route Animation Trigger View

struct RouteAnimationTrigger: View {
    @Binding var shouldTriggerAnimation: Bool
    let onAnimationComplete: () -> Void
    
    var body: some View {
        Color.clear
            .onAppear {
                // Small delay before starting animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    shouldTriggerAnimation = true
                }
                
                // Call completion after animation duration + some buffer
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    onAnimationComplete()
                }
            }
    }
}


#Preview {
    let sampleCoordinates = [
        LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
        LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
        LocationData(latitude: 37.7949, longitude: -122.3994, timestamp: Date()),
        LocationData(latitude: 37.8049, longitude: -122.3894, timestamp: Date()),
        LocationData(latitude: 37.8149, longitude: -122.3794, timestamp: Date())
    ]
    
    let samplePositions = [
        SongPosition(songIndex: 0, progressRatio: 0.2),
        SongPosition(songIndex: 1, progressRatio: 0.5),
        SongPosition(songIndex: 2, progressRatio: 0.8)
    ]
    
    VStack(spacing: 30) {
        Text("Animated Route Drawing")
            .font(.title)
            .padding()
        
        // Static route
        AnimatedRouteView(
            coordinates: sampleCoordinates,
            songPositions: samplePositions,
            lineWidth: 4,
            showSongIndicators: true,
            colorScheme: RunColorScheme.presets[0],
            shouldAnimate: false
        )
        .frame(height: 200)
        .padding()
        
        // Animated route
        AnimatedRouteView(
            coordinates: sampleCoordinates,
            songPositions: samplePositions,
            lineWidth: 4,
            showSongIndicators: true,
            colorScheme: RunColorScheme.presets[1],
            shouldAnimate: true,
            animationDuration: 3.0
        )
        .frame(height: 200)
        .padding()
    }
}