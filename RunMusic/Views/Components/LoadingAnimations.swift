import SwiftUI

// MARK: - Enhanced Loading Components

/// Animated running figure with pulsing effect for loading states
struct AnimatedRunningLoader: View {
    @State private var isAnimating = false
    @State private var scale: CGFloat = 1.0
    
    let size: CGFloat
    let color: Color
    
    init(size: CGFloat = 50, color: Color = .orange) {
        self.size = size
        self.color = color
    }
    
    var body: some View {
        Image(systemName: "figure.run")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [color, color.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .scaleEffect(scale)
            .rotationEffect(.degrees(isAnimating ? 5 : -5))
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isAnimating.toggle()
                }
                
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.15
                }
            }
    }
}

/// Pulsing dots animation for subtle loading indicators
struct PulsingDotsLoader: View {
    @State private var animationPhase: CGFloat = 0
    
    let dotCount: Int
    let dotSize: CGFloat
    let color: Color
    
    init(dotCount: Int = 3, dotSize: CGFloat = 8, color: Color = .orange) {
        self.dotCount = dotCount
        self.dotSize = dotSize
        self.color = color
    }
    
    var body: some View {
        HStack(spacing: dotSize * 0.5) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(opacity(for: index))
                    .scaleEffect(scale(for: index))
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(index) * 0.2),
                        value: animationPhase
                    )
            }
        }
        .onAppear {
            animationPhase = 1
        }
    }
    
    private func opacity(for index: Int) -> Double {
        let phase = (animationPhase + Double(index) * 0.2).truncatingRemainder(dividingBy: 1.0)
        return 0.3 + 0.7 * sin(phase * .pi * 2)
    }
    
    private func scale(for index: Int) -> Double {
        let phase = (animationPhase + Double(index) * 0.2).truncatingRemainder(dividingBy: 1.0)
        return 0.8 + 0.4 * sin(phase * .pi * 2)
    }
}

/// Route drawing animation with progress indicator
struct RouteDrawingLoader: View {
    @State private var progress: CGFloat = 0
    @State private var dashPhase: CGFloat = 0
    
    let lineWidth: CGFloat
    let color: Color
    
    init(lineWidth: CGFloat = 3, color: Color = .orange) {
        self.lineWidth = lineWidth
        self.color = color
    }
    
    var body: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
                .frame(width: 60, height: 60)
            
            // Animated progress circle
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [color, color.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        dash: [8, 4],
                        dashPhase: dashPhase
                    )
                )
                .frame(width: 60, height: 60)
                .rotationEffect(.degrees(-90))
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.0)
                .repeatForever(autoreverses: true)
            ) {
                progress = 1.0
            }
            
            withAnimation(
                .linear(duration: 1.0)
                .repeatForever(autoreverses: false)
            ) {
                dashPhase = 20
            }
        }
    }
}

// MARK: - Loading States with Context

/// Complete loading view with message and animated figure
struct LoadingStateView: View {
    let message: String
    let showProgress: Bool
    let progress: Double?
    
    init(message: String, showProgress: Bool = false, progress: Double? = nil) {
        self.message = message
        self.showProgress = showProgress
        self.progress = progress
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Main loading animation
            if showProgress, let progress = progress {
                VStack(spacing: 16) {
                    RouteDrawingLoader()
                    
                    // Progress bar
                    VStack(spacing: 8) {
                        ProgressView(value: progress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                            .frame(width: 200)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                AnimatedRunningLoader()
            }
            
            // Loading message
            VStack(spacing: 8) {
                Text(message)
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                PulsingDotsLoader()
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Simple Refresh Animation

/// Simple refresh indicator for pull-to-refresh
struct SimpleRefreshLoader: View {
    var body: some View {
        VStack(spacing: 12) {
            RouteDrawingLoader(lineWidth: 2)
                .scaleEffect(0.8)
            
            Text("refreshing...")
                .font(.custom("Helvetica Neue", size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
    }
}