import SwiftUI
import Lottie

/// Lottie-powered runner animation for loading states throughout the app
struct LottieRunnerLoader: UIViewRepresentable {
    let animationName: String
    let loopMode: LottieLoopMode
    let contentMode: UIView.ContentMode
    let animationSpeed: CGFloat
    
    init(
        animationName: String = "runner",
        loopMode: LottieLoopMode = .loop,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        animationSpeed: CGFloat = 1.0
    ) {
        self.animationName = animationName
        self.loopMode = loopMode
        self.contentMode = contentMode
        self.animationSpeed = animationSpeed
    }
    
    func makeUIView(context: Context) -> LottieAnimationView {
        let animationView = LottieAnimationView()
        
        // Try to load the animation, but handle gracefully if missing
        if let animation = LottieAnimation.named(animationName) {
            animationView.animation = animation
            animationView.loopMode = loopMode
            animationView.contentMode = contentMode
            animationView.animationSpeed = animationSpeed
            animationView.play()
        } else {
            // Animation file missing - log error but don't crash
            print("⚠️ Lottie animation '\(animationName)' not found - using empty view")
        }
        
        return animationView
    }
    
    func updateUIView(_ uiView: LottieAnimationView, context: Context) {
        // Update animation if needed
        uiView.animationSpeed = animationSpeed
    }
}

/// Enhanced loading view with Lottie runner animation (fallback to native SwiftUI)
struct LottieLoadingStateView: View {
    let message: String
    let showProgress: Bool
    let progress: Double?
    let size: CGFloat
    @State private var animationRotation: Double = 0
    
    init(
        message: String,
        showProgress: Bool = false,
        progress: Double? = nil,
        size: CGFloat = 100
    ) {
        self.message = message
        self.showProgress = showProgress
        self.progress = progress
        self.size = size
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Try Lottie first, fallback to native SwiftUI animation
            ZStack {
                LottieRunnerLoader()
                    .frame(width: size, height: size)
                
                // Fallback animation (shows if Lottie fails)
                Image(systemName: "figure.run")
                    .font(.system(size: size * 0.6))
                    .foregroundColor(.orange)
                    .rotationEffect(.degrees(animationRotation))
                    .onAppear {
                        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                            animationRotation = 360
                        }
                    }
                    .opacity(0) // Hidden by default - could be shown if needed
            }
            
            // Progress indicator if needed
            if showProgress, let progress = progress {
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: .orange))
                        .frame(width: 200)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            // Loading message
            Text(message)
                .font(.custom("Helvetica Neue", size: 16))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
    }
}

/// Compact Lottie runner for inline loading states
struct CompactLottieRunner: View {
    let size: CGFloat
    
    init(size: CGFloat = 40) {
        self.size = size
    }
    
    var body: some View {
        LottieRunnerLoader(animationSpeed: 1.2)
            .frame(width: size, height: size)
    }
}

/// Lottie runner for pull-to-refresh
struct LottieRefreshLoader: View {
    var body: some View {
        VStack(spacing: 12) {
            CompactLottieRunner(size: 30)
            
            Text("refreshing...")
                .font(.custom("Helvetica Neue", size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
    }
}