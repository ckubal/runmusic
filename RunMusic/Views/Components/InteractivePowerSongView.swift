import SwiftUI

struct InteractivePowerSongView: View {
    @Binding var powerSongDisplay: PowerSongDisplay
    let colorScheme: RunColorScheme
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let onTransformChanged: () -> Void
    
    @State private var lastOffset = CGSize.zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastRotation: Angle = .zero
    
    var body: some View {
        // Dynamic sizing container
        HStack(spacing: 8) {
            // Fire emoji
            Text("🔥")
                .font(.system(size: 24))
                .scaleEffect(1.2)
            
            VStack(alignment: .leading, spacing: 2) {
                // Song name (lowercase like track list)
                Text(powerSongDisplay.songName.lowercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                // Artist name (lowercase like track list)
                Text(powerSongDisplay.artistName.lowercased())
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                // Pace display
                HStack(spacing: 2) {
                    Text(powerSongDisplay.pacePerMile)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Text("per mile")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 24) // Increased padding to prevent text clipping and ensure border overlap
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            colorScheme.primaryColor.color.opacity(0.15), 
                            colorScheme.secondaryColor.color.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: colorScheme.primaryColor.color.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .scaleEffect(powerSongDisplay.scale)
        .rotationEffect(powerSongDisplay.rotation)
        .position(powerSongDisplay.absolutePosition(cardWidth: cardWidth, cardHeight: cardHeight))
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Update position based on drag using percentage-based positioning
                        let currentPosition = powerSongDisplay.absolutePosition(cardWidth: cardWidth, cardHeight: cardHeight)
                        let newX = currentPosition.x + value.translation.width
                        let newY = currentPosition.y + value.translation.height
                        powerSongDisplay.updatePosition(x: newX, y: newY, cardWidth: cardWidth, cardHeight: cardHeight)
                        onTransformChanged()
                    }
                    .onEnded { _ in
                        // Position is now stored in percentage form automatically
                    },
                MagnificationGesture()
                    .onChanged { value in
                        powerSongDisplay.scale = lastScale * value
                        onTransformChanged()
                    }
                    .onEnded { value in
                        lastScale = powerSongDisplay.scale
                    }
            )
            .simultaneously(with:
                RotationGesture()
                    .onChanged { value in
                        powerSongDisplay.rotation = lastRotation + value
                        onTransformChanged()
                    }
                    .onEnded { value in
                        lastRotation = powerSongDisplay.rotation
                    }
            )
        )
        .zIndex(powerSongDisplay.zIndex)
        .onAppear {
            // Initialize gesture states
            lastScale = powerSongDisplay.scale
            lastRotation = powerSongDisplay.rotation
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        
        InteractivePowerSongView(
            powerSongDisplay: .constant(
                PowerSongDisplay(
                    songName: "Blinding Lights",
                    artistName: "The Weeknd",
                    pacePerMile: "7:32"
                )
            ),
            colorScheme: RunColorScheme.presets[0],
            cardWidth: 362,
            cardHeight: 595.56,
            onTransformChanged: {}
        )
    }
}