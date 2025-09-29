import SwiftUI
import FirebaseCore
import GoogleSignIn
import BackgroundTasks

@main
struct RunMusicApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var legacyAuthService = FirebaseAuthService.shared // Keep for transition
    @StateObject private var backgroundSync = SpotifyBackgroundSync.shared
    
    init() {
        print("🚀🚀🚀 RunMusic App Initializing...")
        NSLog("🚀🚀🚀 RunMusic App Initializing (NSLog)")
        FirebaseApp.configure()
        print("🔥 Firebase configured")
        NSLog("🔥 Firebase configured (NSLog)")
        
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plistDict = NSDictionary(contentsOfFile: path),
           let clientId = plistDict["CLIENT_ID"] as? String {
            let config = GIDConfiguration(clientID: clientId)
            GIDSignIn.sharedInstance.configuration = config
        }
        
        // Register background task handlers
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.runmusic.spotify-sync", using: nil) { task in
            if let refreshTask = task as? BGAppRefreshTask {
                SpotifyBackgroundSync.shared.handleBackgroundAppRefresh(task: refreshTask)
            }
        }
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.runmusic.newrun-check", using: nil) { task in
            if let refreshTask = task as? BGAppRefreshTask {
                NewRunDetectionService.shared.handleBackgroundAppRefresh(task: refreshTask)
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authViewModel)
                .environmentObject(legacyAuthService) // Keep for transition
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.didEnterBackgroundNotification
                )) { _ in
                    // Schedule background tasks when app goes to background
                    NewRunDetectionService.shared.scheduleBackgroundRefresh()
                }
        }
    }
}