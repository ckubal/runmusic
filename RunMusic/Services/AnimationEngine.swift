import Foundation
import SwiftUI
import CoreLocation
import AVFoundation

// MARK: - Animation Data Models

struct AnimationFrame {
    let timestamp: TimeInterval
    let runnerPosition: CGPoint
    let routeProgress: Double // 0.0 to 1.0
    let currentSong: SpotifyTrack?
    let visibleSongMarkers: [AnimationSongMarker]
    let songTextState: SongTextState
}

struct AnimationSongMarker {
    let id: String
    let position: CGPoint
    let song: SpotifyTrack
    let appearanceTime: TimeInterval
    let isVisible: Bool
}

struct SongTextState {
    let currentSong: SpotifyTrack?
    let opacity: Double
    let animationType: SongTextAnimation
}

enum SongTextAnimation {
    case appearing
    case visible
    case disappearing
    case hidden
}

// MARK: - Animation Engine

@MainActor
class AnimationEngine: ObservableObject {
    @Published var currentFrame: AnimationFrame?
    @Published var isPlaying: Bool = false
    @Published var progress: Double = 0.0
    
    private var animationTimer: Timer?
    private var startTime: Date?
    
    // Animation Configuration
    let totalDuration: TimeInterval
    let frameRate: Double = 60.0 // fps
    let routeCoordinates: [LocationData]
    let songs: [SpotifyTrack]
    let canvasSize: CGSize
    
    // Cached Animation Data
    private var frames: [AnimationFrame] = []
    internal var routePoints: [CGPoint] = []
    private var songMarkers: [AnimationSongMarker] = []
    
    init(run: RunActivity, canvasSize: CGSize, fixedDuration: TimeInterval? = nil) {
        self.totalDuration = fixedDuration ?? run.elapsedTime
        self.routeCoordinates = run.routeCoordinates
        self.songs = run.spotifyTracks ?? []
        self.canvasSize = canvasSize
        
        prepareAnimationData()
    }
    
    // MARK: - Animation Control
    
    func play() {
        guard !isPlaying else { return }
        
        isPlaying = true
        startTime = Date()
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / frameRate, repeats: true) { [weak self] _ in
            self?.updateFrame()
        }
    }
    
    func pause() {
        isPlaying = false
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    func stop() {
        pause()
        progress = 0.0
        currentFrame = frames.first
    }
    
    func seek(to progress: Double) {
        self.progress = max(0.0, min(1.0, progress))
        let frameIndex = Int(progress * Double(frames.count - 1))
        currentFrame = frames[safe: frameIndex]
    }
    
    // MARK: - Frame Updates
    
    private func updateFrame() {
        guard let startTime = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        progress = min(elapsed / totalDuration, 1.0)
        
        if progress >= 1.0 {
            stop()
            return
        }
        
        let frameIndex = Int(progress * Double(frames.count - 1))
        currentFrame = frames[safe: frameIndex]
    }
    
    // MARK: - Animation Data Preparation
    
    private func prepareAnimationData() {
        convertRouteToScreenCoordinates()
        createSongMarkers()
        generateAnimationFrames()
    }
    
    private func convertRouteToScreenCoordinates() {
        guard !routeCoordinates.isEmpty else { return }
        
        // Calculate bounding box
        let latitudes = routeCoordinates.map { $0.latitude }
        let longitudes = routeCoordinates.map { $0.longitude }
        
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0
        
        // Add padding (10% of canvas)
        let padding: CGFloat = 0.1 * min(canvasSize.width, canvasSize.height)
        let drawableSize = CGSize(
            width: canvasSize.width - (padding * 2),
            height: canvasSize.height - (padding * 2)
        )
        
        // Convert GPS to screen coordinates
        routePoints = routeCoordinates.map { coordinate in
            let normalizedLat = (coordinate.latitude - minLat) / (maxLat - minLat)
            let normalizedLon = (coordinate.longitude - minLon) / (maxLon - minLon)
            
            return CGPoint(
                x: padding + (normalizedLon * drawableSize.width),
                y: padding + ((1.0 - normalizedLat) * drawableSize.height) // Flip Y for screen coordinates
            )
        }
    }
    
    private func createSongMarkers() {
        guard !songs.isEmpty, !routePoints.isEmpty else { return }
        
        songMarkers = songs.compactMap { song in
            guard let firstCoordinate = routeCoordinates.first else { return nil }
            let songStartTime = song.playedAt.timeIntervalSince(firstCoordinate.timestamp ?? Date())
            
            if songStartTime < 0 {
                return nil
            }
            
            // Find position along route for this song's start time
            let songProgress = songStartTime / totalDuration
            let routeIndex = Int(songProgress * Double(routePoints.count - 1))
            
            guard routeIndex < routePoints.count else { return nil }
            
            return AnimationSongMarker(
                id: song.id ?? UUID().uuidString,
                position: routePoints[routeIndex],
                song: song,
                appearanceTime: songStartTime,
                isVisible: false
            )
        }
    }
    
    private func generateAnimationFrames() {
        let totalFrames = Int(totalDuration * frameRate)
        frames = []
        
        for frameIndex in 0..<totalFrames {
            let timestamp = (Double(frameIndex) / frameRate)
            let progress = timestamp / totalDuration
            
            // Calculate runner position with smooth interpolation
            let runnerPosition = interpolateRunnerPosition(progress: progress)
            
            // Determine current song
            let currentSong = getCurrentSong(at: timestamp)
            
            // Update visible song markers
            let visibleMarkers = songMarkers.map { marker in
                AnimationSongMarker(
                    id: marker.id,
                    position: marker.position,
                    song: marker.song,
                    appearanceTime: marker.appearanceTime,
                    isVisible: timestamp >= marker.appearanceTime
                )
            }
            
            // Calculate song text state
            let songTextState = calculateSongTextState(at: timestamp, currentSong: currentSong)
            
            let frame = AnimationFrame(
                timestamp: timestamp,
                runnerPosition: runnerPosition,
                routeProgress: progress,
                currentSong: currentSong,
                visibleSongMarkers: visibleMarkers,
                songTextState: songTextState
            )
            
            frames.append(frame)
        }
        
        // Set initial frame
        currentFrame = frames.first
    }
    
    private func getCurrentSong(at timestamp: TimeInterval) -> SpotifyTrack? {
        let startDate = routeCoordinates.first?.timestamp ?? Date()
        let songTime = startDate.addingTimeInterval(timestamp)
        
        // Find the song that was playing at this time
        return songs.first { song in
            let playedAt = song.playedAt
            let songDuration = TimeInterval(song.durationMs) / 1000.0
            let songEnd = playedAt.addingTimeInterval(songDuration)
            return playedAt <= songTime && songTime <= songEnd
        }
    }
    
    private func interpolateRunnerPosition(progress: Double) -> CGPoint {
        guard !routePoints.isEmpty else { return .zero }
        guard routePoints.count > 1 else { return routePoints.first ?? .zero }
        
        let totalPoints = routePoints.count
        let exactIndex = progress * Double(totalPoints - 1)
        let lowerIndex = Int(exactIndex.rounded(.down))
        let upperIndex = min(lowerIndex + 1, totalPoints - 1)
        
        // If we're at the end or have identical indices
        if lowerIndex >= upperIndex || lowerIndex >= totalPoints - 1 {
            return routePoints[lowerIndex]
        }
        
        // Calculate interpolation factor
        let t = exactIndex - Double(lowerIndex)
        let point1 = routePoints[lowerIndex]
        let point2 = routePoints[upperIndex]
        
        // Linear interpolation between the two points
        return CGPoint(
            x: point1.x + (point2.x - point1.x) * t,
            y: point1.y + (point2.y - point1.y) * t
        )
    }
    
    private func calculateSongTextState(at timestamp: TimeInterval, currentSong: SpotifyTrack?) -> SongTextState {
        guard let song = currentSong else {
            return SongTextState(currentSong: nil, opacity: 0.0, animationType: .hidden)
        }
        
        // Find when this song started relative to the run
        guard let firstCoordinate = routeCoordinates.first else {
            return SongTextState(currentSong: song, opacity: 1.0, animationType: .visible)
        }
        let songStartTime = song.playedAt.timeIntervalSince(firstCoordinate.timestamp ?? Date())
        
        let timeSinceSongStart = timestamp - songStartTime
        let animationDuration: TimeInterval = 0.5 // 500ms fade
        
        if timeSinceSongStart < animationDuration {
            // Appearing
            let opacity = timeSinceSongStart / animationDuration
            return SongTextState(currentSong: song, opacity: opacity, animationType: .appearing)
        } else {
            // Fully visible
            return SongTextState(currentSong: song, opacity: 1.0, animationType: .visible)
        }
    }
}

// MARK: - Utilities

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Animation Preview Component

struct AnimatedRunCardPreview: View {
    @StateObject private var animationEngine: AnimationEngine
    let run: RunActivity
    
    init(run: RunActivity) {
        self.run = run
        self._animationEngine = StateObject(wrappedValue: AnimationEngine(
            run: run,
            canvasSize: CGSize(width: 300, height: 400), // Preview size
            fixedDuration: 12.0 // Use same 12-second animation duration as video export
        ))
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Animation Canvas
            ZStack {
                // Background (same as static card)
                RoundedRectangle(cornerRadius: 16)
                    .fill(run.portraitSettings.colorScheme?.gradient ?? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                // Animated Content
                Canvas { context, size in
                    drawAnimatedContent(context: context, size: size)
                }
                .frame(width: 300, height: 400)
            }
            
            // Controls
            HStack {
                Button(animationEngine.isPlaying ? "Pause" : "Play") {
                    if animationEngine.isPlaying {
                        animationEngine.pause()
                    } else {
                        animationEngine.play()
                    }
                }
                .buttonStyle(.borderedProminent)
                
                Button("Stop") {
                    animationEngine.stop()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Text("\(Int(animationEngine.progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
            }
            
            // Progress Bar
            ProgressView(value: animationEngine.progress)
                .progressViewStyle(LinearProgressViewStyle())
        }
        .padding()
    }
    
    private func drawAnimatedContent(context: GraphicsContext, size: CGSize) {
        guard let frame = animationEngine.currentFrame else { return }
        
        // Draw route path (up to current progress)
        drawRoutePath(context: context, progress: frame.routeProgress)
        
        // Draw runner position
        drawRunner(context: context, position: frame.runnerPosition)
        
        // Draw visible song markers
        drawSongMarkers(context: context, markers: frame.visibleSongMarkers)
        
        // Draw song text
        drawSongText(context: context, textState: frame.songTextState, size: size)
    }
    
    private func drawRoutePath(context: GraphicsContext, progress: Double) {
        guard let engine = animationEngine as? AnimationEngine else { return }
        let routePoints = engine.routePoints
        guard routePoints.count > 1 else { return }
        
        let progressIndex = Int(progress * Double(routePoints.count - 1))
        let visiblePoints = Array(routePoints.prefix(progressIndex + 1))
        
        guard visiblePoints.count > 1 else { return }
        
        var path = Path()
        path.move(to: visiblePoints[0])
        for point in visiblePoints.dropFirst() {
            path.addLine(to: point)
        }
        
        context.stroke(
            path,
            with: .color(.white),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        )
    }
    
    private func drawRunner(context: GraphicsContext, position: CGPoint) {
        let runnerSize: CGFloat = 8
        let runnerRect = CGRect(
            x: position.x - runnerSize/2,
            y: position.y - runnerSize/2,
            width: runnerSize,
            height: runnerSize
        )
        
        context.fill(
            Path(ellipseIn: runnerRect),
            with: .color(.white)
        )
        
        // Add glow effect
        context.fill(
            Path(ellipseIn: runnerRect.insetBy(dx: -2, dy: -2)),
            with: .color(.white.opacity(0.3))
        )
    }
    
    private func drawSongMarkers(context: GraphicsContext, markers: [AnimationSongMarker]) {
        for marker in markers where marker.isVisible {
            let markerSize: CGFloat = 6
            let markerRect = CGRect(
                x: marker.position.x - markerSize/2,
                y: marker.position.y - markerSize/2,
                width: markerSize,
                height: markerSize
            )
            
            context.fill(
                Path(ellipseIn: markerRect),
                with: .color(.yellow)
            )
        }
    }
    
    private func drawSongText(context: GraphicsContext, textState: SongTextState, size: CGSize) {
        guard let song = textState.currentSong else { return }
        
        let songText = "\(song.name) - \(song.artist)"
        let textOpacity = textState.opacity
        
        // Position text at bottom of canvas
        let textPosition = CGPoint(x: size.width / 2, y: size.height - 50)
        
        context.draw(
            Text(songText)
                .font(.headline)
                .foregroundColor(.white.opacity(textOpacity)),
            at: textPosition,
            anchor: .center
        )
    }
}