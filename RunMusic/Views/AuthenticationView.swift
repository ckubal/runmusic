import SwiftUI
import SafariServices

struct AuthenticationView: View {
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService
    @StateObject private var stravaService = StravaService.shared
    @StateObject private var spotifyService = SpotifyService.shared
    @State private var showingSafari = false
    @State private var currentAuthService: AuthService? = nil
    @State private var authURL: URL? = nil
    @State private var showTutorial = false
    @State private var showLoginPrompt = false
    @Environment(\.colorScheme) var colorScheme
    
    enum AuthService {
        case strava, spotify
    }
    
    struct AuthItem: Identifiable {
        let id = UUID()
        let service: AuthService
        let url: URL
    }
    
    var body: some View {
        ZStack {
            // Gradient background matching shareable card aesthetic
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.15),
                    Color.pink.opacity(0.08),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                
                // App branding with consistent aesthetic
                VStack(spacing: 20) {
                    // Logo
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: Color.orange.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        Image(systemName: "figure.run")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("run the tunes")
                            .font(.custom("Helvetica Neue", size: 42))
                            .fontWeight(.bold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        // Removed hardcoded username - will show actual username when logged in
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    Text("turn your runs into shareable stories")
                        .font(.custom("Helvetica Neue", size: 18))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Animated runner
                    LottieLoadingStateView(message: "", showProgress: false, size: 60)
                        .padding(.top, 20)
                }
                
                Spacer()
                
                // Main action buttons
                VStack(spacing: 20) {
                    // Primary: Connect to Strava
                    Button {
                        if let url = stravaService.authURL {
                            currentAuthService = .strava
                            authURL = url
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.run.circle.fill")
                                .font(.system(size: 20))
                            Text("connect to strava")
                                .font(.custom("Helvetica Neue", size: 18))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color.orange, Color.pink.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(color: Color.orange.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    
                    // Secondary: See what the app does
                    Button {
                        showTutorial = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.circle")
                                .font(.system(size: 16))
                            Text("see what run the tunes does")
                                .font(.custom("Helvetica Neue", size: 16))
                        }
                        .foregroundColor(.orange)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
                        )
                    }
                    
                    // Tertiary: Existing account login
                    Button {
                        showLoginPrompt = true
                    } label: {
                        Text("already have an account? log in.")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.secondary)
                            .underline()
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding()
        }
        .sheet(item: Binding<AuthItem?>(
            get: { 
                if let authURL = authURL, let currentAuthService = currentAuthService {
                    return AuthItem(service: currentAuthService, url: authURL)
                }
                return nil
            },
            set: { _ in 
                authURL = nil
                currentAuthService = nil
            }
        )) { authItem in
            SafariView(url: authItem.url) { url in
                switch authItem.service {
                case .strava:
                    stravaService.handleAuthCallback(url: url)
                case .spotify:
                    Task {
                        await spotifyService.handleAuthCallback(url: url)
                    }
                }
                authURL = nil
                currentAuthService = nil
            }
        }
        .fullScreenCover(isPresented: $showTutorial) {
            TutorialView(showTutorial: $showTutorial)
        }
        .sheet(isPresented: $showLoginPrompt) {
            LoginPromptView {
                showLoginPrompt = false
            }
        }
        .onOpenURL { url in
            if url.scheme == "runthetunes" {
                if url.host == "runthetunes.app" {
                    stravaService.handleAuthCallback(url: url)
                } else if url.host == "spotify-auth" {
                    Task {
                        await spotifyService.handleAuthCallback(url: url)
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StartStravaAuthFromTutorial"))) { _ in
            // Trigger Strava auth when requested from tutorial
            if let url = stravaService.authURL {
                currentAuthService = .strava
                authURL = url
            }
        }
    }
}

// MARK: - Tutorial View

struct TutorialView: View {
    @Binding var showTutorial: Bool
    @State private var currentPage = 0
    @StateObject private var stravaService = StravaService.shared
    
    let totalPages = 3
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.15),
                    Color.pink.opacity(0.08),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation bar
                HStack {
                    Button {
                        showTutorial = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 20))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        tutorialPage(for: page)
                            .tag(page)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
                // Navigation controls
                HStack {
                    // Back button (hidden on first page)
                    Button {
                        withAnimation {
                            currentPage -= 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("back")
                        }
                        .font(.custom("Helvetica Neue", size: 16))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .stroke(Color.orange.opacity(0.5), lineWidth: 1.5)
                        )
                    }
                    .opacity(currentPage > 0 ? 1 : 0)
                    .disabled(currentPage == 0)
                    
                    Spacer()
                    
                    // Page indicators
                    HStack(spacing: 8) {
                        ForEach(0..<totalPages, id: \.self) { page in
                            Circle()
                                .fill(page == currentPage ? Color.orange : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Spacer()
                    
                    // Next/Get Started button
                    if currentPage < totalPages - 1 {
                        Button {
                            withAnimation {
                                currentPage += 1
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("next")
                                Image(systemName: "chevron.right")
                            }
                            .font(.custom("Helvetica Neue", size: 16))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.orange, Color.pink.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    } else {
                        // Connect to Strava button on last page
                        Button {
                            showTutorial = false
                            // Send notification to trigger Strava auth
                            NotificationCenter.default.post(name: NSNotification.Name("StartStravaAuthFromTutorial"), object: nil)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "figure.run.circle.fill")
                                Text("connect to strava to get started")
                            }
                            .font(.custom("Helvetica Neue", size: 18))
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
    
    @ViewBuilder
    private func tutorialPage(for page: Int) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                switch page {
                case 0:
                    // Page 1: What Run Tunes does
                    VStack(spacing: 20) {
                        Text("your runs, your music,\nyour story")
                            .font(.custom("Helvetica Neue", size: 32))
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .padding(.top, 20)
                        
                        // Mock run list
                        MockRunListView()
                            .frame(height: 400)
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                            .padding(.horizontal)
                        
                        VStack(spacing: 12) {
                            Text("track every run")
                                .font(.custom("Helvetica Neue", size: 20))
                                .fontWeight(.semibold)
                            
                            Text("see all your runs in one place with\nmusic, pace, and route details")
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                case 1:
                    // Page 2: Shareable cards
                    VStack(spacing: 20) {
                        Text("create beautiful\nshareable cards")
                            .font(.custom("Helvetica Neue", size: 32))
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .padding(.top, 20)
                        
                        // Mock shareable card
                        MockShareableCardView()
                            .frame(width: 300, height: 490)
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.1), radius: 20, x: 0, y: 10)
                        
                        VStack(spacing: 12) {
                            Text("share your journey")
                                .font(.custom("Helvetica Neue", size: 20))
                                .fontWeight(.semibold)
                            
                            Text("turn your runs into instagram-ready\nstories with album art and power songs")
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 40)
                    }
                    
                case 2:
                    // Page 3: Connect everything
                    VStack(spacing: 20) {
                        Text("connect your\nfavorite apps")
                            .font(.custom("Helvetica Neue", size: 32))
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .padding(.top, 20)
                        
                        VStack(spacing: 30) {
                            // Strava connection
                            ConnectionCard(
                                icon: "figure.run.circle.fill",
                                iconColor: .orange,
                                title: "strava",
                                description: "import your runs and routes",
                                isRequired: true
                            )
                            
                            // Spotify connection
                            ConnectionCard(
                                icon: "music.note.circle.fill",
                                iconColor: .green,
                                title: "spotify",
                                description: "match music to your runs",
                                isRequired: false
                            )
                            
                            // Firebase account
                            ConnectionCard(
                                icon: "person.circle.fill",
                                iconColor: .blue,
                                title: "create account",
                                description: "sync across devices",
                                isRequired: false
                            )
                        }
                        .padding(.horizontal)
                        
                        Text("start with strava, add more later")
                            .font(.custom("Helvetica Neue", size: 16))
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                    
                default:
                    EmptyView()
                }
            }
            .padding(.bottom, 100)
        }
    }
}

// MARK: - Mock Views for Tutorial

struct MockRunListView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("your runs")
                    .font(.custom("Helvetica Neue", size: 24))
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding()
            .background(Color(.systemBackground))
            
            // Mock runs
            ScrollView {
                VStack(spacing: 12) {
                    MockRunRow(
                        title: "morning run",
                        location: "golden gate park",
                        distance: "5.2 mi",
                        time: "42:15",
                        pace: "8:07",
                        songs: "6 songs • dua lipa, the weeknd"
                    )
                    
                    MockRunRow(
                        title: "lunch run",
                        location: "embarcadero",
                        distance: "3.1 mi",
                        time: "25:30",
                        pace: "8:13",
                        songs: "4 songs • olivia rodrigo, drake"
                    )
                }
                .padding()
            }
        }
        .background(Color(.systemBackground))
    }
}

struct MockRunRow: View {
    let title: String
    let location: String
    let distance: String
    let time: String
    let pace: String
    let songs: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Mini route preview
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color.orange.opacity(0.3), Color.pink.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 60, height: 60)
                .overlay(
                    Path { path in
                        path.move(to: CGPoint(x: 10, y: 45))
                        path.addCurve(to: CGPoint(x: 50, y: 15), 
                                     control1: CGPoint(x: 20, y: 35), 
                                     control2: CGPoint(x: 40, y: 25))
                    }
                    .stroke(Color.orange, lineWidth: 2)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 16))
                    .fontWeight(.semibold)
                
                Text(location)
                    .font(.custom("Helvetica Neue", size: 14))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    Label(distance, systemImage: "figure.run")
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                    
                    Label(time, systemImage: "clock")
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                    
                    Label(pace, systemImage: "speedometer")
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Image(systemName: "music.note")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    
                    Text(songs)
                        .font(.custom("Helvetica Neue", size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct MockShareableCardView: View {
    var body: some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black)
            
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading) {
                        Text("run the tunes")
                            .font(.custom("Helvetica Neue", size: 14))
                            .foregroundColor(.white.opacity(0.8))
                        
                        Text("@runner123")
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                        Text("jun 15")
                            .font(.custom("Helvetica Neue", size: 12))
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
                
                // Location
                HStack {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14))
                    Text("golden gate park in san francisco")
                        .font(.custom("Helvetica Neue", size: 14))
                }
                .foregroundColor(.orange)
                
                // Distance
                Text("5.2 mi")
                    .font(.custom("Helvetica Neue", size: 48))
                    .fontWeight(.bold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.orange, Color.pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text("morning run")
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.orange)
                
                // Route preview
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 120)
                    .overlay(
                        Path { path in
                            path.move(to: CGPoint(x: 30, y: 90))
                            path.addCurve(to: CGPoint(x: 250, y: 30), 
                                         control1: CGPoint(x: 80, y: 70), 
                                         control2: CGPoint(x: 200, y: 50))
                        }
                        .stroke(
                            LinearGradient(
                                colors: [Color.orange, Color.pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 3
                        )
                    )
                
                // Song list
                VStack(alignment: .leading, spacing: 8) {
                    MockSongRow(number: "i", title: "levitating", artist: "dua lipa")
                    MockSongRow(number: "ii", title: "blinding lights", artist: "the weeknd")
                    MockSongRow(number: "iii", title: "good 4 u", artist: "olivia rodrigo")
                }
                .padding(.horizontal)
                
                // Power song
                HStack {
                    Text("🔥")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("nostalgia")
                            .font(.custom("Helvetica Neue", size: 11))
                            .fontWeight(.bold)
                        Text("pusha t")
                            .font(.custom("Helvetica Neue", size: 9))
                            .opacity(0.8)
                        Text("8:03 per mile")
                            .font(.custom("Helvetica Neue", size: 10))
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.2))
                )
                .offset(x: 80, y: -20)
                
                Spacer()
            }
            .padding()
        }
    }
}

struct MockSongRow: View {
    let number: String
    let title: String
    let artist: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.custom("Helvetica Neue", size: 12))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.custom("Helvetica Neue", size: 11))
                    .fontWeight(.medium)
                
                Text(artist)
                    .font(.custom("Helvetica Neue", size: 9))
                    .opacity(0.7)
            }
            .foregroundColor(.white)
            
            Spacer()
        }
    }
}

struct ConnectionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    let isRequired: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(iconColor)
                .frame(width: 60)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.custom("Helvetica Neue", size: 18))
                        .fontWeight(.semibold)
                    
                    if isRequired {
                        Text("required")
                            .font(.custom("Helvetica Neue", size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                }
                
                Text(description)
                    .font(.custom("Helvetica Neue", size: 14))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Login Prompt View (Updated with Dual Provider)

struct LoginPromptView: View {
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService
    @StateObject private var authViewModel = AuthViewModel()
    @State private var isProcessing = false
    @State private var statusMessage = ""
    @Environment(\.colorScheme) var colorScheme
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            // Gradient background matching DualProviderAuthView
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.15),
                    Color.pink.opacity(0.08),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                VStack(spacing: 20) {
                    // User icon with orange/pink theme
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange, Color.pink.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                            .shadow(color: Color.orange.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                    
                    Text("welcome back")
                        .font(.custom("Helvetica Neue", size: 32))
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color.pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    if isProcessing {
                        VStack(spacing: 12) {
                            Text("syncing your connected accounts...")
                                .font(.custom("Helvetica Neue", size: 16))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            if !statusMessage.isEmpty {
                                Text(statusMessage)
                                    .font(.custom("Helvetica Neue", size: 14))
                                    .foregroundColor(.orange)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        Text("sign in to sync your runs and music")
                            .font(.custom("Helvetica Neue", size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Spacer()
                
                VStack(spacing: 15) {
                    if let errorMessage = authViewModel.errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 5)
                    }

                    // Google Sign-In Button
                    Button {
                        Task {
                            await enhancedGoogleSignIn()
                        }
                    } label: {
                        HStack {
                            if firebaseAuth.isLoading || isProcessing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(colorScheme == .dark ? .white : .black)
                            } else {
                                Image("google_logo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 22, height: 22)
                                    .padding(.leading, 15)
                            }
                            
                            Spacer()
                            
                            Text(getGoogleButtonText())
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Spacer()
                        }
                        .frame(height: 50)
                        .frame(maxWidth: 320)
                    }
                    .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .disabled(firebaseAuth.isLoading || isProcessing)
                    
                    // Apple Sign-In Button
                    Button {
                        Task {
                            await enhancedAppleSignIn()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "apple.logo")
                                .font(.system(size: 20))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.leading, 15)
                            
                            Spacer()
                            
                            Text("Sign in with Apple")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                            
                            Spacer()
                        }
                        .frame(height: 50)
                        .frame(maxWidth: 320)
                    }
                    .background(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                    .cornerRadius(8)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                    .disabled(authViewModel.authSheetState != .idle || isProcessing)
                    
                    Button("cancel") {
                        onDismiss()
                    }
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.secondary)
                    .disabled(isProcessing)
                    .padding(.top, 10)
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .padding()
        }
        .onChange(of: authViewModel.authSheetState) { _, newState in
            if newState == .successful {
                Task {
                    await performPostAuthSync()
                }
            }
        }
    }
    
    @MainActor
    private func enhancedGoogleSignIn() async {
        await firebaseAuth.signInWithGoogle()
        
        guard firebaseAuth.isAuthenticated else {
            return
        }
        
        await performPostAuthSync()
    }
    
    @MainActor
    private func enhancedAppleSignIn() async {
        authViewModel.startAppleSignIn()
    }
    
    @MainActor
    private func performPostAuthSync() async {
        isProcessing = true
        statusMessage = "syncing your connected accounts..."
        
        // Wait for the token sync to complete (triggered by Firebase auth state listener)
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds to allow sync to complete
        
        // Check authentication status after sync
        let stravaAuth = StravaService.shared.isAuthenticated
        let spotifyAuth = SpotifyService.shared.isAuthenticated
        
        if stravaAuth && spotifyAuth {
            statusMessage = "all accounts restored! ✓"
        } else if stravaAuth && !spotifyAuth {
            statusMessage = "strava restored! spotify needs reconnection"
        } else if !stravaAuth && spotifyAuth {
            statusMessage = "spotify restored! strava needs reconnection"  
        } else {
            statusMessage = "welcome back! please reconnect your accounts"
        }
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        isProcessing = false
        onDismiss()
    }
    
    private func getGoogleButtonText() -> String {
        if firebaseAuth.isLoading {
            return "signing in..."
        } else if isProcessing {
            return "syncing accounts..."
        } else {
            return "Sign in with Google"
        }
    }
}

// MARK: - Safari View

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: (URL) -> Void
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safariVC = SFSafariViewController(url: url)
        safariVC.delegate = context.coordinator
        return safariVC
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDismiss: (URL) -> Void
        
        init(onDismiss: @escaping (URL) -> Void) {
            self.onDismiss = onDismiss
        }
        
        func safariViewController(_ controller: SFSafariViewController, initialLoadDidRedirectTo URL: URL) {
            handleRedirect(URL)
        }
        
        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        }
        
        private func handleRedirect(_ URL: URL) {
            if URL.scheme == "runthetunes" {
                DispatchQueue.main.async {
                    self.onDismiss(URL)
                }
            }
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(FirebaseAuthService.shared)
}