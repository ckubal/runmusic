import SwiftUI
import CoreLocation

struct EnhancedAssetView: View {
    let asset: CanvasAsset
    let isSelected: Bool
    let canvasSize: CGSize
    let onSelect: () -> Void
    let onUpdate: (CanvasAsset) -> Void
    let onEdit: ((CanvasAsset) -> Void)?
    
    // MARK: - Gesture State Management
    @State private var accumulatedPosition: CGPoint = .zero
    @State private var accumulatedScale: CGFloat = 1.0
    @State private var accumulatedRotation: Double = 0.0
    
    @State private var currentDragOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    @State private var currentRotation: Double = 0.0
    
    var body: some View {
        assetContent
            .overlay(
                selectionOverlay
                    .opacity(isSelected ? 1 : 0)
            )
            .scaleEffect(accumulatedScale * currentScale)
            .rotationEffect(.degrees(accumulatedRotation + currentRotation))
            .position(
                x: accumulatedPosition.x + currentDragOffset.width,
                y: accumulatedPosition.y + currentDragOffset.height
            )
            .gesture(isSelected ? dragGesture : nil)
            .gesture(isSelected ? simultaneousRotationAndScale : nil)
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    onSelect()
                }
            }
            .onTapGesture(count: 2) {
                // Double tap to edit (if editable)
                if asset.editableType != .none {
                    onEdit?(asset)
                }
            }
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: isSelected)
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.9), value: currentDragOffset)
            .zIndex(isSelected ? 1000 : asset.zIndex)
            .onAppear {
                accumulatedPosition = asset.position
                accumulatedScale = asset.scale
                accumulatedRotation = asset.rotation
            }
    }
    
    // MARK: - Asset Content Views
    
    @ViewBuilder
    private var assetContent: some View {
        switch asset.type {
        case .text:
            textAssetView
            
        case .image:
            imageAssetView
            
        case .titleDistance:
            titleDistanceAssetView
            
        case .route:
            routeAssetView
            
        case .songList:
            songListAssetView
            
        case .pace, .date, .time:
            statAssetView
            
        case .weather:
            weatherAssetView
            
        case .powerSong:
            powerSongAssetView
            
        case .albumArt:
            albumArtAssetView
            
        case .location:
            locationAssetView
            
        case .stats:
            statsClusterAssetView
        }
    }
    
    // MARK: - Individual Asset Views
    
    private var textAssetView: some View {
        Text(asset.content.displayText)
            .font(.system(
                size: asset.fontSize,
                weight: asset.fontWeight,
                design: .rounded
            ))
            .foregroundColor(asset.color)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
                    .contentShape(Rectangle())
            )
    }
    
    private var imageAssetView: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.3), Color.white.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 120, height: 120)
            .overlay(
                Image(systemName: "photo.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
    }
    
    private var titleDistanceAssetView: some View {
        VStack(spacing: 4) {
            if case .titleDistance(let title, let distance, let unit) = asset.content {
                Text("\(String(format: "%.1f", distance)) \(unit)")
                    .font(.system(size: asset.fontSize * 1.2, weight: .heavy, design: .rounded))
                    .foregroundColor(asset.color)
                
                Text(title.lowercased())
                    .font(.system(size: asset.fontSize * 0.6, weight: .bold, design: .rounded))
                    .foregroundColor(asset.color.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.1))
                .contentShape(Rectangle())
        )
    }
    
    private var routeAssetView: some View {
        Group {
            if case .route(let coordinates) = asset.content {
                RoutePathView(
                    coordinates: coordinates,
                    songPositions: [],
                    lineWidth: 3.0,
                    showSongIndicators: false,
                    colorScheme: RunColorScheme.presets[0] // Default color scheme
                )
                .frame(width: 150, height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.05))
                        .contentShape(Rectangle())
                )
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
    
    private var songListAssetView: some View {
        Group {
            if case .songList(let tracks, let powerSongId) = asset.content {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(tracks.prefix(10).enumerated()), id: \.offset) { index, track in
                        let isPowerSong = track.id == powerSongId
                        
                        HStack(spacing: 12) {
                            // Roman numeral OR fire emoji for power song
                            if isPowerSong {
                                Text("🔥")
                                    .font(.system(size: 16))
                                    .frame(width: 24, alignment: .leading)
                            } else {
                                Text(romanNumeral(for: index + 1))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white)
                                    .frame(width: 24, alignment: .leading)
                            }
                            
                            // Song title - artist
                            Text("\(track.name.lowercased()) - \(track.artist.lowercased())")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(isPowerSong ? .orange : .white)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Rectangle()
                                .fill(Color.black)
                        )
                    }
                }
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
    
    private var statAssetView: some View {
        HStack(spacing: 4) {
            Image(systemName: asset.type.systemIcon)
                .font(.system(size: asset.fontSize * 0.8))
                .foregroundColor(asset.color.opacity(0.7))
            
            Text(asset.content.displayText)
                .font(.system(size: asset.fontSize, weight: asset.fontWeight))
                .foregroundColor(asset.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(asset.color.opacity(0.1))
                .contentShape(Capsule())
        )
    }
    
    private var weatherAssetView: some View {
        Group {
            if case .weather(let weather) = asset.content {
                HStack(spacing: 4) {
                    Text(weather.condition.emoji)
                        .font(.system(size: asset.fontSize))
                    
                    Text("\(Int(weather.temperature))°F")
                        .font(.system(size: asset.fontSize, weight: asset.fontWeight))
                        .foregroundColor(asset.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(asset.color.opacity(0.1))
                        .contentShape(Capsule())
                )
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
    
    private var powerSongAssetView: some View {
        Group {
            if case .powerSong(let track, let pace) = asset.content {
                HStack(spacing: 12) {
                    // Large fire emoji spanning the height of the text
                    Text("🔥")
                        .font(.system(size: 36))
                    
                    // Text content
                    VStack(alignment: .leading, spacing: 2) {
                        // Bold song title
                        Text(track.name.lowercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        // Artist name
                        Text(track.artist.lowercased())
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        
                        // Pace with larger time and smaller "per mile"
                        if let pace = pace {
                            HStack(spacing: 2) {
                                Text(pace)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white)
                                Text("per mile")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            // Weather-based gradient - default to orange/red fire colors
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.8),
                                    Color.red.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
    
    private var albumArtAssetView: some View {
        Group {
            if case .albumArt(let imageURL, let imageData, let albumName, let artistName) = asset.content {
            Group {
                if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Placeholder for album art
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            VStack(spacing: 2) {
                                Image(systemName: "music.note")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white.opacity(0.8))
                                
                                Text(albumName.prefix(12))
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                        )
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            .contentShape(Rectangle())
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
    
    private var locationAssetView: some View {
        HStack(spacing: 4) {
            Image(systemName: "location.fill")
                .font(.system(size: asset.fontSize * 0.8))
                .foregroundColor(asset.color)
            
            Text(asset.content.displayText.lowercased())
                .font(.system(size: asset.fontSize, weight: asset.fontWeight))
                .foregroundColor(asset.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(asset.color.opacity(0.1))
                .contentShape(Capsule())
        )
    }
    
    private var statsClusterAssetView: some View {
        Group {
            if case .stats(let stats) = asset.content {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    statBadge(icon: "speedometer", text: stats.pace, color: .green)
                    statBadge(icon: "clock", text: stats.time, color: .blue)
                }
                
                HStack(spacing: 12) {
                    statBadge(icon: "calendar", text: stats.date, color: .purple)
                    if let weather = stats.weather {
                        statBadge(icon: "thermometer", text: weather, color: .orange)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.1))
                    .contentShape(Rectangle())
            )
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
    
    private func statBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(color.opacity(0.7))
            
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
    
    private func romanNumeral(for number: Int) -> String {
        let romanNumerals = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", 
                           "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx"]
        return number <= romanNumerals.count ? romanNumerals[number - 1] : "\(number)"
    }
    
    // MARK: - Selection Overlay
    
    private var selectionOverlay: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(Color.blue, lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.1))
            )
            .padding(-6)
    }
    
    // MARK: - Gesture System (copied from RunTunes)
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                currentDragOffset = value.translation
            }
            .onEnded { value in
                let newX = max(20, min(canvasSize.width - 20, accumulatedPosition.x + value.translation.width))
                let newY = max(40, min(canvasSize.height - 40, accumulatedPosition.y + value.translation.height))
                accumulatedPosition = CGPoint(x: newX, y: newY)
                
                var updatedAsset = asset
                updatedAsset.position = accumulatedPosition
                onUpdate(updatedAsset)
                
                currentDragOffset = .zero
            }
    }
    
    private var simultaneousRotationAndScale: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    currentScale = value
                }
                .onEnded { value in
                    accumulatedScale = max(0.3, min(3.0, accumulatedScale * value))
                    
                    var updatedAsset = asset
                    updatedAsset.scale = accumulatedScale
                    onUpdate(updatedAsset)
                    
                    currentScale = 1.0
                },
            
            RotationGesture()
                .onChanged { value in
                    currentRotation = value.degrees
                }
                .onEnded { value in
                    accumulatedRotation = (accumulatedRotation + value.degrees).truncatingRemainder(dividingBy: 360)
                    
                    var updatedAsset = asset
                    updatedAsset.rotation = accumulatedRotation
                    onUpdate(updatedAsset)
                    
                    currentRotation = 0
                }
        )
    }
}

#Preview {
    let sampleRun = RunActivity(
        id: "1",
        name: "Morning Run",
        date: Date(),
        distance: 5000,
        elapsedTime: 1800,
        averagePace: 360,
        startLocation: LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
        endLocation: LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date()),
        routeCoordinates: [
            LocationData(latitude: 37.7749, longitude: -122.4194, timestamp: Date()),
            LocationData(latitude: 37.7849, longitude: -122.4094, timestamp: Date())
        ],
        city: "San Francisco",
        neighborhood: "Golden Gate Park"
    )
    
    let asset = CanvasAsset.createTitleDistance(for: sampleRun)
    
    EnhancedAssetView(
        asset: asset,
        isSelected: true,
        canvasSize: CGSize(width: 400, height: 600),
        onSelect: {},
        onUpdate: { _ in },
        onEdit: nil
    )
    .frame(width: 400, height: 600)
    .background(Color.gray.opacity(0.2))
}