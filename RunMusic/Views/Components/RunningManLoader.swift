import SwiftUI

// Simple placeholder loader components
struct RunningManLoader: View {
    let size: CGFloat
    let color: Color
    let speed: Double
    
    init(size: CGFloat = 40, color: Color = .orange, speed: Double = 1.0) {
        self.size = size
        self.color = color
        self.speed = speed
    }
    
    var body: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: color))
            .scaleEffect(size / 40)
    }
}

struct CompactRunningLoader: View {
    let size: CGFloat
    let color: Color
    
    var body: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: color))
            .scaleEffect(size / 20)
    }
}

struct EnhancedLoadingView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                .scaleEffect(1.5)
            Text(message)
                .font(.custom("Helvetica Neue", size: 16))
                .foregroundColor(.secondary)
        }
    }
}