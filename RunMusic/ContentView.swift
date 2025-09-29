import SwiftUI
import UserNotifications

struct ContentView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @EnvironmentObject private var firebaseAuth: FirebaseAuthService // Legacy service for transition
    @StateObject private var stravaService = StravaService.shared
    @StateObject private var spotifyService = SpotifyService.shared
    @StateObject private var pushNotificationService = PushNotificationService.shared
    @State private var showUsernameSelection = false
    @State private var needsUsernameSetup = false
    @State private var selectedRunId: String?
    
    var body: some View {
        Group {
            if stravaService.isAuthenticated {
                // Once user has connected Strava, show their runs immediately
                // Google/Apple auth is optional and can be prompted later
                RunCardStackView(selectedRunId: $selectedRunId)
            } else if firebaseAuth.isAuthenticated {
                // User has Firebase auth but Strava needs reconnection
                // Show main app with reconnection prompts instead of full login screen
                RunCardStackView(selectedRunId: $selectedRunId)
            } else {
                // Show Strava authentication first for new users
                AuthenticationView()
            }
        }
        .onAppear {
            print("🚀 RunMusic App Started")
            NSLog("🚀 RunMusic App Started (NSLog)")
            print("📍 Strava authenticated: \(stravaService.isAuthenticated)")
            NSLog("📍 Strava authenticated: %@", stravaService.isAuthenticated ? "true" : "false")
            print("🎵 Spotify authenticated: \(spotifyService.isAuthenticated)")
            NSLog("🎵 Spotify authenticated: %@", spotifyService.isAuthenticated ? "true" : "false")
            print("🔥 Firebase authenticated: \(firebaseAuth.isAuthenticated)")
            NSLog("🔥 Firebase authenticated: %@", firebaseAuth.isAuthenticated ? "true" : "false")
            
            // Set up notification handling
            setupNotificationHandling()
        }
        .onChange(of: authViewModel.isUserPermanentlyAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                // Check username setup only when user signs in with Google/Apple
                Task {
                    await UserPreferences.shared.syncFromFirebase()
                    await checkForUsernameSetup()
                }
            }
        }
        .sheet(isPresented: $showUsernameSelection) {
            UsernameSelectionView(
                onComplete: { username in
                    print("✅ Username selected: \(username)")
                    showUsernameSelection = false
                    needsUsernameSetup = false
                },
                onSkip: {
                    print("⏭️ Username selection skipped")
                    showUsernameSelection = false
                    needsUsernameSetup = false
                }
            )
            .interactiveDismissDisabled() // Prevent dismissing without completing
        }
        .onOpenURL { url in
            print("🔄 ContentView: Received URL callback: \(url)")
            if url.scheme == "runthetunes" {
                if url.host == "runthetunes.app" {
                    print("🔄 ContentView: Routing to Strava service")
                    stravaService.handleAuthCallback(url: url)
                } else if url.host == "spotify-auth" {
                    print("🔄 ContentView: Routing to Spotify service")
                    Task {
                        await spotifyService.handleAuthCallback(url: url)
                    }
                } else if url.host == "run", let runId = url.pathComponents.last {
                    print("🔄 ContentView: Opening run from deep link: \(runId)")
                    selectedRunId = runId
                }
            }
        }
    }
    
    @MainActor
    private func checkForUsernameSetup() async {
        guard let userId = authViewModel.getCurrentUserID() else { return }
        
        do {
            let userProfile = try await FirestoreService.shared.getUserProfile(userId: userId)
            
            // Check if username is missing or empty
            if userProfile?.username?.isEmpty != false {
                needsUsernameSetup = true
                showUsernameSelection = true
            }
        } catch {
            print("❌ Error checking username setup: \(error)")
        }
    }
    
    private func setupNotificationHandling() {
        // Set up UNUserNotificationCenter delegate to handle notification taps
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        
        // Handle any pending notifications when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            handlePendingNotifications()
        }
    }
    
    private func handlePendingNotifications() {
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            for notification in notifications {
                if let runId = notification.request.content.userInfo["runId"] as? String {
                    Task { @MainActor in
                        print("📱 Opening run from notification: \(runId)")
                        self.selectedRunId = runId
                        // Clear the notification once handled
                        UNUserNotificationCenter.current().removeDeliveredNotifications(
                            withIdentifiers: [notification.request.identifier]
                        )
                    }
                }
            }
        }
    }
}

// Notification handling delegate
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if let runId = PushNotificationService.shared.handleNotificationResponse(response) {
                // Open the specific run when notification is tapped
                print("📱 Notification tapped, opening run: \(runId)")
                NotificationCenter.default.post(
                    name: NSNotification.Name("OpenRunFromNotification"),
                    object: runId
                )
            }
        }
        
        completionHandler()
    }
    
    // Handle notifications when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and sound even when app is in foreground
        completionHandler([.banner, .sound])
    }
}

#Preview {
    ContentView()
}