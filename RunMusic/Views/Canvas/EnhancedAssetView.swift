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
    
    // Debug state
    @State private var debugUpdateCount = 0
    
    var body: some View {
        assetContent
            .overlay(
                selectionOverlay
                    .opacity(isSelected ? 1 : 0)
            )
            .scaleEffect(accumulatedScale * currentScale, anchor: .center)
            .rotationEffect(.degrees(accumulatedRotation + currentRotation), anchor: .center)
            .position(
                x: accumulatedPosition.x + currentDragOffset.width,
                y: accumulatedPosition.y + currentDragOffset.height
            )
            .highPriorityGesture(isSelected ? dragGesture : nil)
            .simultaneousGesture(isSelected ? simultaneousRotationAndScale : nil)
            .onTapGesture {
                print("🎯 Asset tapped: \(asset.type)")
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
                print("🎯 APPEAR: \(asset.type) - position: \(asset.position), scale: \(asset.scale), zIndex: \(asset.zIndex)")
                if asset.type == .albumArt {
                    print("🎨 ALBUM ART ASSET: onAppear triggered for album art!")
                }
                accumulatedPosition = asset.position
                accumulatedScale = asset.scale
                accumulatedRotation = asset.rotation
            }
            .onChange(of: asset.position) { oldPosition, newPosition in
                print("🎯 POSITION CHANGED: \(asset.type)")
                print("   📍 Old: \(oldPosition)")
                print("   📍 New: \(newPosition)")
                print("   📍 Accumulated before: \(accumulatedPosition)")
                
                // Update accumulated position when asset position changes
                accumulatedPosition = newPosition
                print("   📍 Accumulated after: \(accumulatedPosition)")
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
                .onAppear {
                    print("🎨 ASSET SWITCH: About to render albumArt asset")
                }
            
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
                    .font(.system(size: asset.fontSize * 0.8, weight: .medium, design: .rounded))
                    .foregroundColor(asset.color.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } else {
                // Debug fallback for title/distance
                Text("⚠️ Title Error")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.2))
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
                    songPositions: nil,
                    lineWidth: 3.0,
                    showSongIndicators: false,
                    colorScheme: RunColorScheme.presets.first // Default color scheme
                )
                .frame(width: 150, height: 150)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.05))
                        .contentShape(Rectangle())
                )
            } else {
                // Debug fallback
                Text("⚠️ Invalid Content")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.2))
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
                // Debug fallback
                Text("⚠️ Invalid Content")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.2))
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
                // Debug fallback
                Text("⚠️ Invalid Content")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.2))
            }
        }
    }
    
    private var powerSongAssetView: some View {
        Group {
            if case .powerSong(let track, let pace) = asset.content {
                HStack(spacing: 8) {
                    // Fire emoji scaled with font size
                    Text("🔥")
                        .font(.system(size: asset.fontSize * 2.5))
                    
                    // Text content
                    VStack(alignment: .leading, spacing: 1) {
                        // Bold song title
                        Text(track.name.lowercased())
                            .font(.system(size: asset.fontSize * 1.2, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        // Artist name
                        Text(track.artist.lowercased())
                            .font(.system(size: asset.fontSize, weight: .regular))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                        
                        // Pace with scaled fonts
                        if let pace = pace {
                            HStack(spacing: 1) {
                                Text(pace)
                                    .font(.system(size: asset.fontSize * 1.1, weight: .medium))
                                    .foregroundColor(.white)
                                Text("per mile")
                                    .font(.system(size: asset.fontSize * 0.8, weight: .regular))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            // Weather-based gradient - 40% opacity as requested
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.4),
                                    Color.red.opacity(0.4)
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
                // Debug fallback
                Text("⚠️ Invalid Content")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.2))
            }
        }
    }
    
    private var albumArtAssetView: some View {
        Group {
            if case .albumArt(let imageURL, let imageData, let albumName, let artistName) = asset.content {
                Group {
                    if let imageData = imageData, let uiImage = UIImage(data: imageData) {
                        // Use cached image data if available
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else if let imageURL = imageURL, !imageURL.isEmpty, let url = URL(string: imageURL) {
                        // Load image from URL using AsyncImage
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure(let error):
                                // Show error placeholder
                                albumArtPlaceholder(albumName: albumName, isError: true)
                                    .onAppear {
                                        print("🎨 Album art failed to load for '\(albumName)': \(error.localizedDescription)")
                                    }
                            case .empty:
                                // Loading placeholder
                                albumArtPlaceholder(albumName: albumName, isError: false)
                            @unknown default:
                                albumArtPlaceholder(albumName: albumName, isError: false)
                            }
                        }
                        .onAppear {
                            print("🎨 Loading album art for '\(albumName)': \(imageURL)")
                        }
                    } else {
                        // No image URL - show placeholder
                        albumArtPlaceholder(albumName: albumName, isError: false)
                    }
                }
                .frame(width: 80, height: 80) // 80x80 as requested
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .contentShape(Rectangle())
                .onAppear {
                    print("🎨 ALBUM ART VIEW: Rendering album art for '\(albumName)'")
                    print("🎨 ALBUM ART VIEW: Asset position: \(asset.position), scale: \(asset.scale), zIndex: \(asset.zIndex)")
                    print("🎨 ALBUM ART VIEW: imageURL: \(imageURL ?? "nil"), hasImageData: \(imageData != nil)")
                }
            } else {
                // Debug fallback
                Text("⚠️ Invalid Content")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Color.red.opacity(0.2))
            }
        }
    }
    
    @ViewBuilder
    private func albumArtPlaceholder(albumName: String, isError: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: isError ? 
                        [Color.red.opacity(0.6), Color.orange.opacity(0.4)] :
                        [Color.purple.opacity(0.6), Color.blue.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                VStack(spacing: 2) {
                    Image(systemName: isError ? "exclamationmark.triangle" : "music.note")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(albumName.prefix(12))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
            )
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
                HStack(spacing: 8) {
                    // Date
                    Text(stats.date)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("•")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    
                    // Time
                    Text(stats.time)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                    
                    Text("•")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    
                    // Pace
                    Text(stats.pace)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green.opacity(0.9))
                    
                    // Weather (if available)
                    if let weather = stats.weather {
                        Text("•")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                        
                        Text(weather)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange.opacity(0.9))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.4))
                        .contentShape(Rectangle())
                )
            } else {
                // Fallback for invalid content - show debug info
                Text("Stats Error")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.2))
                    )
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
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                print("🎯 DRAGGING: \(asset.type) - offset: \(value.translation)")
                currentDragOffset = value.translation
            }
            .onEnded { value in
                debugUpdateCount += 1
                let newX = max(20, min(canvasSize.width - 20, accumulatedPosition.x + value.translation.width))
                let newY = max(40, min(canvasSize.height - 40, accumulatedPosition.y + value.translation.height))
                
                print("🎯 DRAG ENDED: \(asset.type)")
                print("   📍 Old position: \(accumulatedPosition)")
                print("   📍 Translation: \(value.translation)")
                print("   📍 New position: CGPoint(x: \(newX), y: \(newY))")
                print("   🔄 Update count: \(debugUpdateCount)")
                
                // Update accumulated position immediately to prevent snap-back
                accumulatedPosition = CGPoint(x: newX, y: newY)
                
                // Create updated asset and notify parent
                var updatedAsset = asset
                updatedAsset.position = accumulatedPosition
                
                print("   💾 Calling onUpdate with position: \(updatedAsset.position)")
                onUpdate(updatedAsset)
                
                // Reset drag offset only after position is updated
                withAnimation(.easeOut(duration: 0.1)) {
                    currentDragOffset = .zero
                }
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