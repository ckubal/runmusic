import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct SettingsView: View {
    @ObservedObject private var stravaService = StravaService.shared
    @ObservedObject private var spotifyService = SpotifyService.shared
    @ObservedObject private var userPreferences = UserPreferences.shared
    @ObservedObject private var photoService = PhotoService.shared
    @ObservedObject private var backgroundSync = SpotifyBackgroundSync.shared
    @ObservedObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var pushNotificationService = PushNotificationService.shared
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showingStravaSafari = false
    @State private var showingSpotifyImport = false
    @State private var showingImportGuide = false
    @State private var comprehensiveStats: SpotifyBackgroundSync.ComprehensiveTrackStats?
    @State private var showingLogoutConfirmation = false
    @State private var showingStravaLogoutConfirmation = false
    @State private var showingSpotifyLogoutConfirmation = false
    @State private var showingAuthChoice = false
    @State private var showingUsernameSelection = false
    @State private var spotifyTestResult = ""
    @State private var isTestingSpotifyAPI = false
    @Environment(\.dismiss) private var dismiss
    
    // Computed property to check if user is using metric units
    private var isMetricUnits: Bool {
        userPreferences.distanceUnit == .kilometers && userPreferences.temperatureUnit == .celsius
    }
    
    // Toggle between metric and imperial units
    private func toggleUnits() {
        if isMetricUnits {
            // Switch to imperial
            userPreferences.distanceUnit = .miles
            userPreferences.temperatureUnit = .fahrenheit
        } else {
            // Switch to metric
            userPreferences.distanceUnit = .kilometers
            userPreferences.temperatureUnit = .celsius
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                // Account Section
                Section("accounts") {
                    // Strava Account
                    HStack {
                        Image(systemName: "figure.run.circle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("strava")
                                .font(.custom("Helvetica Neue", size: 18))
                                .foregroundColor(.primary)
                            
                            if stravaService.isAuthenticated {
                                Text("connected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.green)
                            } else {
                                Text("not connected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if stravaService.isAuthenticated {
                            Button("sign out") {
                                showingStravaLogoutConfirmation = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.red)
                        } else {
                            Button("connect") {
                                showingStravaSafari = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Spotify Account
                    HStack {
                        Image(systemName: "music.note.list")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("spotify")
                                .font(.custom("Helvetica Neue", size: 18))
                                .foregroundColor(.primary)
                            
                            if spotifyService.isAuthenticated {
                                Text("connected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.green)
                            } else {
                                Text("not connected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if spotifyService.isAuthenticated {
                            Button("sign out") {
                                showingSpotifyLogoutConfirmation = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.red)
                        } else {
                            Button("connect") {
                                if let authURL = spotifyService.authURL {
                                    print("🔵 SettingsView: Opening Spotify auth in system Safari")
                                    UIApplication.shared.open(authURL)
                                }
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section("public endpoint") {
                    Button("Generate Public Tokens") {
                        Task {
                            await stravaService.migrateToPublicTokens()
                        }
                    }
                    .disabled(!stravaService.isAuthenticated)
                    
                    if stravaService.isAuthenticated {
                        Text("After connecting to Strava, tap this to enable your public homepage endpoint")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("firebase") {
                    Button("Sign in with Google") {
                        Task {
                            await FirebaseAuthService.shared.signInWithGoogle()
                        }
                    }
                }
            }
            .navigationTitle("settings")
            .alert("Sign Out", isPresented: $showingStravaLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    stravaService.logout()
                }
            } message: {
                Text("Are you sure you want to sign out of Strava?")
            }
            .alert("Sign Out", isPresented: $showingSpotifyLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    spotifyService.logout()
                }
            } message: {
                Text("Are you sure you want to sign out of Spotify?")
            }
            .fullScreenCover(isPresented: $showingStravaSafari) {
                if let authURL = stravaService.authURL {
                    SafariView(url: authURL) { url in
                        stravaService.handleAuthCallback(url: url)
                    }
                } else {
                    Text("Unable to load Strava authentication")
                }
            }
        }
    }
}

/*
    var bodyBackup: some View {
        NavigationView {
            List {
                // Account Section
                Section("accounts") {
                    // Strava Account
                    HStack {
                        Image(systemName: "figure.run.circle.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("strava")
                                .font(.custom("Helvetica Neue", size: 18))
                                .foregroundColor(.primary)
                            
                            if stravaService.isAuthenticated {
                                Text("connected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.green)
                            } else {
                                Text("not connected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if stravaService.isAuthenticated {
                            Button("sign out") {
                                showingStravaLogoutConfirmation = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.red)
                        } else {
                            Button("connect") {
                                showingStravaSafari = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Spotify Account
                    HStack {
                        Image(systemName: "music.note.list")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("spotify")
                                .font(.custom("Helvetica Neue", size: 18))
                                .foregroundColor(.primary)
                            
                            if spotifyService.isAuthenticated {
                                Text("connected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.green)
                            } else {
                                Text("not connected")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if spotifyService.isAuthenticated {
                            Button("sign out") {
                                showingSpotifyLogoutConfirmation = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.red)
                        } else {
                            Button("connect") {
                                if let authURL = spotifyService.authURL {
                                    print("🔵 SettingsView: Opening Spotify auth in system Safari")
                                    UIApplication.shared.open(authURL)
                                }
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.green)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Firebase/Google Account - Make tappable when not authenticated
                    Button(action: {
                        if !authViewModel.isUserPermanentlyAuthenticated {
                            showingAuthChoice = true
                        }
                    }) {
                        HStack {
                            Image(systemName: "icloud.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text("run the tunes account")
                                        .font(.custom("Helvetica Neue", size: 18))
                                        .foregroundColor(.primary)
                                    
                                    if !authViewModel.isUserPermanentlyAuthenticated {
                                        HStack(spacing: 2) {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundColor(.red)
                                                .font(.caption)
                                            Text("Account not connected")
                                                .font(.custom("Helvetica Neue", size: 10))
                                                .foregroundColor(.red)
                                        }
                                    }
                                }
                                
                                if authViewModel.isUserPermanentlyAuthenticated {
                                    if let userProfile = authViewModel.userProfile {
                                        Text(userProfile.email.isEmpty ? "signed in" : userProfile.email)
                                            .font(.custom("Helvetica Neue", size: 12))
                                            .foregroundColor(.green)
                                    } else {
                                        Text("connected")
                                            .font(.custom("Helvetica Neue", size: 12))
                                            .foregroundColor(.green)
                                    }
                                } else {
                                    Text("sync customizations across devices")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if authViewModel.isUserPermanentlyAuthenticated {
                                Button("sign out") {
                                    showingLogoutConfirmation = true
                                }
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.red)
                            } else {
                                Button("sign in") {
                                    showingAuthChoice = true
                                }
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                }
                
                // Username Section - Only show if user has Firebase account
                if authViewModel.isUserPermanentlyAuthenticated {
                    Section("profile") {
                        HStack {
                            Image(systemName: "at")
                                .foregroundColor(.purple)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("username")
                                    .font(.custom("Helvetica Neue", size: 18))
                                    .foregroundColor(.primary)
                                
                                if let userProfile = authViewModel.userProfile, 
                                   let username = userProfile.username, !username.isEmpty {
                                    Text("@\(username)")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.green)
                                } else {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                        Text("no username set")
                                            .font(.custom("Helvetica Neue", size: 12))
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if !hasUsername {
                                Button("set up") {
                                    showingUsernameSelection = true
                                }
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.purple)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Spotify Extended History Section  
                if spotifyService.isAuthenticated {
                    Section("spotify history") {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.green)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("extended streaming history")
                                    .font(.custom("Helvetica Neue", size: 18))
                                    .foregroundColor(.primary)
                                
                                // Show comprehensive Firebase stats if available
                                if let stats = comprehensiveStats, stats.totalTracks > 0 {
                                    Text(stats.displayText)
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.green)
                                } else if spotifyService.hasImportedTracks() {
                                    // Fallback to local imported tracks info
                                    let info = spotifyService.getImportedTracksInfo()
                                    Text("\(info.count.formatted()) tracks imported")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.green)
                                    Text("\(info.dateRange)")
                                        .font(.custom("Helvetica Neue", size: 10))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("import your complete spotify history")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Button(spotifyService.hasImportedTracks() ? "add more" : "import") {
                                showingImportGuide = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.green)
                        }
                        .padding(.vertical, 4)
                        
                        // Quick access to import guide
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("how to get your data")
                                    .font(.custom("Helvetica Neue", size: 18))
                                    .foregroundColor(.primary)
                                
                                Text("step-by-step guide to export from spotify")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button("guide") {
                                showingImportGuide = true
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Spotify Sync Status (Auto-enabled when connected)
                if spotifyService.isAuthenticated {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("listening history sync")
                                        .font(.custom("Helvetica Neue", size: 18))
                                        .foregroundColor(.primary)
                                    
                                    Text("automatically collecting your spotify activity")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                // Show that it's always active when Spotify is connected
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title3)
                            }
                            
                            // Sync Statistics
                            if backgroundSync.totalHistoricalTracks > 0 {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(backgroundSync.totalHistoricalTracks) tracks collected")
                                            .font(.custom("Helvetica Neue", size: 14))
                                            .foregroundColor(.primary)
                                        
                                        if let lastSync = backgroundSync.syncSettings?.lastSyncAt {
                                            Text("last sync: \(RelativeDateTimeFormatter().localizedString(for: lastSync, relativeTo: Date()))")
                                                .font(.custom("Helvetica Neue", size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    // Sync status indicator
                                    switch backgroundSync.syncStatus {
                                    case .syncing:
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    case .completed(let count):
                                        HStack(spacing: 4) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                                .font(.caption)
                                            Text("+\(count)")
                                                .font(.custom("Helvetica Neue", size: 11))
                                                .foregroundColor(.green)
                                        }
                                    case .failed:
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                    default:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        // Debug Tools
                        if authViewModel.isUserPermanentlyAuthenticated {
                            debugSection
                            legacyDataSection
                        }
                        
                        // Clear all historical data option
                        if backgroundSync.totalHistoricalTracks > 0 || spotifyService.hasImportedTracks() {
                            Button("clear all spotify data") {
                                Task {
                                    if spotifyService.hasImportedTracks() {
                                        await spotifyService.clearImportedTracks()
                                    }
                                    await backgroundSync.clearAllHistoricalData()
                                }
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.red)
                            .padding(.top, 8)
                        }
                    } header: {
                        Text("spotify history")
                    } footer: {
                        Text("automatically collects your Spotify listening history in the background to match with future runs")
                            .font(.custom("Helvetica Neue", size: 12))
                    }
                }
                
                // Preferences Section
                Section("preferences") {
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("units")
                                .font(.custom("Helvetica Neue", size: 18))
                                .foregroundColor(.primary)
                            
                            Text(isMetricUnits ? "metric (km, °c)" : "imperial (mi, °f)")
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: toggleUnits) {
                            Text(isMetricUnits ? "metric" : "imperial")
                                .font(.custom("Helvetica Neue", size: 14))
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Card Display Options
                    HStack {
                        Image(systemName: "location")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        Text("show city by default")
                            .font(.custom("Helvetica Neue", size: 18))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Toggle("", isOn: $userPreferences.showCityByDefault)
                            .tint(.orange)
                    }
                    .padding(.vertical, 4)
                    
                    HStack {
                        Image(systemName: "music.note")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        Text("show songs by default")
                            .font(.custom("Helvetica Neue", size: 18))
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Toggle("", isOn: $userPreferences.showSongsByDefault)
                            .tint(.green)
                    }
                    .padding(.vertical, 4)
                    
                    // Push Notifications
                    HStack {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.orange)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("run completion notifications")
                                .font(.custom("Helvetica Neue", size: 18))
                                .foregroundColor(.primary)
                            
                            if pushNotificationService.authorizationStatus == .authorized {
                                Text("get notified when your run cards are ready")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.green)
                            } else if pushNotificationService.authorizationStatus == .denied {
                                Text("enable in system settings to get notifications")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.red)
                            } else {
                                Text("get notified when your run cards are ready")
                                    .font(.custom("Helvetica Neue", size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if pushNotificationService.authorizationStatus == .notDetermined {
                            Button("enable") {
                                Task {
                                    let granted = await pushNotificationService.requestPermission()
                                    if granted {
                                        userPreferences.pushNotificationsEnabled = true
                                    }
                                }
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.orange)
                        } else if pushNotificationService.authorizationStatus == .authorized {
                            Toggle("", isOn: $userPreferences.pushNotificationsEnabled)
                                .tint(.orange)
                        } else if pushNotificationService.authorizationStatus == .denied {
                            Button("settings") {
                                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(settingsUrl)
                                }
                            }
                            .font(.custom("Helvetica Neue", size: 12))
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Photo Library Access - simplified to avoid layout loops
                    photoLibrarySection
                }
                
                // App Info Section
                Section("about") {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.gray)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("run the tunes")
                                .font(.custom("Helvetica Neue", size: 18))
                                .foregroundColor(.primary)
                            Text("version 1.0")
                                .font(.custom("Helvetica Neue", size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                
                // Debug Section (only show in debug builds)
                #if DEBUG
                Section("developer options") {
                    // Manual Spotify Sync
                    if spotifyService.isAuthenticated {
                        Button {
                            Task {
                                print("🔧 Manual sync button pressed")
                                await SpotifyBackgroundSync.shared.performManualSync()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.title2)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("manual spotify sync")
                                        .font(.custom("Helvetica Neue", size: 18))
                                        .foregroundColor(.primary)
                                    
                                    switch backgroundSync.syncStatus {
                                    case .syncing:
                                        HStack {
                                            ProgressView()
                                                .scaleEffect(0.7)
                                            Text("syncing...")
                                                .font(.custom("Helvetica Neue", size: 12))
                                                .foregroundColor(.secondary)
                                        }
                                    case .completed(let tracks):
                                        Text("last sync: \(tracks) new tracks")
                                            .font(.custom("Helvetica Neue", size: 12))
                                            .foregroundColor(.green)
                                    case .failed(let error):
                                        Text("sync failed: \(error.localizedDescription)")
                                            .font(.custom("Helvetica Neue", size: 12))
                                            .foregroundColor(.red)
                                            .lineLimit(2)
                                    default:
                                        Text("tap to sync recent spotify tracks")
                                            .font(.custom("Helvetica Neue", size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    // Test Spotify API
                    Button {
                        testSpotifyAPI()
                    } label: {
                        HStack {
                            if isTestingSpotifyAPI {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.purple)
                            } else {
                                Image(systemName: "waveform.circle.fill")
                                    .foregroundColor(.purple)
                                    .font(.title2)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isTestingSpotifyAPI ? "testing spotify api..." : "test spotify api")
                                    .font(.custom("Helvetica Neue", size: 18))
                                    .foregroundColor(.primary)
                                
                                if spotifyTestResult.isEmpty {
                                    Text("diagnose authentication issues")
                                        .font(.custom("Helvetica Neue", size: 12))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(spotifyTestResult)
                                        .font(.custom("Helvetica Neue", size: 11))
                                        .foregroundColor(spotifyTestResult.contains("SUCCESS") ? .green : .red)
                                        .lineLimit(3)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(isTestingSpotifyAPI)
                    
                    // View Sync Settings
                    if let settings = backgroundSync.syncSettings {
                        HStack {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.gray)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("sync settings")
                                    .font(.custom("Helvetica Neue", size: 18))
                                    .foregroundColor(.primary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("enabled: \(settings.isBackgroundSyncEnabled ? "yes" : "no")")
                                    Text("frequency: \(settings.syncFrequencyMinutes)m")
                                    if let lastSync = settings.lastSyncAt {
                                        Text("last: \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                                    }
                                    Text("total tracks: \(settings.totalTracksCollected)")
                                }
                                .font(.custom("Helvetica Neue", size: 11))
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                #endif
            }
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.large)
            .alert("sign out of run the tunes account?", isPresented: $showingLogoutConfirmation) {
                Button("cancel", role: .cancel) { }
                Button("proceed to log out", role: .destructive) {
                    Task {
                        await authViewModel.signOut()
                    }
                }
            } message: {
                Text("logging out will remove access to your saved runs and settings across devices. you can sign back in anytime to restore your data.")
            }
            .alert("sign out of strava?", isPresented: $showingStravaLogoutConfirmation) {
                Button("cancel", role: .cancel) { }
                Button("proceed to log out", role: .destructive) {
                    stravaService.logout()
                }
            } message: {
                Text("logging out will remove access to your running data. you'll need to reconnect strava to see your runs.")
            }
            .alert("sign out of spotify?", isPresented: $showingSpotifyLogoutConfirmation) {
                Button("cancel", role: .cancel) { }
                Button("proceed to log out", role: .destructive) {
                    spotifyService.logout()
                }
            } message: {
                Text("logging out will remove access to your music data. you'll need to reconnect spotify to match songs with your runs.")
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("done") {
                        dismiss()
                    }
                    .font(.custom("Helvetica Neue", size: 16))
                    .foregroundColor(.orange)
                }
            }
        }
        .sheet(isPresented: $showingStravaSafari) {
            if let authURL = stravaService.authURL {
                SafariView(url: authURL) { url in
                    stravaService.handleAuthCallback(url: url)
                    showingStravaSafari = false
                }
            }
        }
        .sheet(isPresented: $showingImportGuide) {
            SpotifyImportGuideView()
        }
        .sheet(isPresented: $showingAuthChoice) {
            DualProviderAuthView()
                .environmentObject(authViewModel)
        }
        .sheet(isPresented: $showingUsernameSelection) {
            UsernameSelectionView(
                onComplete: { username in
                    print("✅ Username updated in Settings: \(username)")
                    showingUsernameSelection = false
                },
                onSkip: {
                    print("⏭️ Username selection skipped from Settings")
                    showingUsernameSelection = false
                }
            )
            .environmentObject(authViewModel)
        }
        .onAppear {
            Task {
                await loadComprehensiveStats()
            }
        }
        .onChange(of: authViewModel.isUserPermanentlyAuthenticated) { oldValue, newValue in
            if newValue && !oldValue {
                // User just signed in, reload stats
                Task {
                    await loadComprehensiveStats()
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var hasUsername: Bool {
        guard let userProfile = authViewModel.userProfile,
              let username = userProfile.username else {
            return false
        }
        return !username.isEmpty
    }
    
    @ViewBuilder
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("check firebase storage") {
                Task {
                    await checkFirebaseStorage()
                    await loadComprehensiveStats()
                }
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.blue)
            .padding(.top, 4)
            
            Button("debug spotify sync setup") {
                debugSpotifySync()
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.orange)
            .padding(.top, 2)
            
            Button("test spotify api directly") {
                testSpotifyAPI()
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.green)
            .padding(.top, 2)
            
            Button("diagnose spotify authentication") {
                diagnoseSpotifyAuth()
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.purple)
            .padding(.top, 2)
            
            Button("test manual sync") {
                testManualSync()
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.purple)
            .padding(.top, 2)
            
            Button("debug firebase data") {
                debugFirebaseData()
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.orange)
            .padding(.top, 2)
        }
    }
    
    @ViewBuilder 
    private var legacyDataSection: some View {
        VStack(spacing: 8) {
            Button("🚀 restore August data from legacy collection") {
                Task {
                    guard let userId = authViewModel.getCurrentUserID() else {
                        print("❌ No authenticated user for restoration")
                        return
                    }
                    
                    print("🚀 Starting legacy data restoration...")
                    do {
                        try await FirestoreService.shared.restoreLegacyTracksToUnifiedCollection(userId: userId)
                        let validation = try await FirestoreService.shared.validateRestoredData(userId: userId)
                        print("✅ Restoration completed successfully!")
                        print("📊 Final counts - Legacy: \(validation.legacy), Unified: \(validation.unified), Restored: \(validation.restored)")
                        await loadComprehensiveStats()
                    } catch {
                        print("❌ Restoration failed: \(error)")
                    }
                }
            }
            .font(.custom("Helvetica Neue", size: 11))
            .foregroundColor(.green)
            .padding(.top, 4)
            
            Button("🗑️ clean up legacy subcollection data") {
                Task {
                    guard let userId = authViewModel.getCurrentUserID() else {
                        print("❌ No authenticated user for cleanup")
                        return
                    }
                    
                    print("🗑️ Starting legacy data cleanup...")
                    do {
                        try await FirestoreService.shared.cleanupLegacySpotifyData(userId: userId)
                        print("✅ Cleanup completed successfully!")
                        await loadComprehensiveStats()
                    } catch {
                        print("❌ Cleanup failed: \(error)")
                    }
                }
            }
            .font(.custom("Helvetica Neue", size: 11))
            .foregroundColor(.red)
            .padding(.top, 4)
            
            Button("debug firebase connection") {
                Task {
                    print("🔍 Starting Firebase connection debug...")
                    await FirestoreService.shared.debugFirebaseConnection()
                }
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.orange)
            .padding(.top, 4)
        }
    }
    
    private func checkFirebaseStorage() async {
        guard let userId = authViewModel.getCurrentUserID() else {
            print("❌ No authenticated user")
            return
        }
        
        print("🔍 FIREBASE STORAGE DEBUG for user: \(userId)")
        print("🔍 ==========================================")
        
        do {
            // Check imported tracks in Firebase
            let importedTracks = try await FirestoreService.shared.getImportedSpotifyTracks(userId: userId)
            print("☁️ Firebase imported tracks: \(importedTracks.count)")
            
            if !importedTracks.isEmpty {
                let dateRange = SpotifyService.shared.getDateRange(for: importedTracks)
                print("☁️ Date range: \(dateRange)")
                print("☁️ First track: \(importedTracks.first?.name ?? "unknown") by \(importedTracks.first?.artist ?? "unknown")")
                print("☁️ Last track: \(importedTracks.last?.name ?? "unknown") by \(importedTracks.last?.artist ?? "unknown")")
            }
            
            // Check background sync data
            let backgroundTracks = await backgroundSync.getTracksForTimeRange(
                startTime: Date().addingTimeInterval(-7 * 24 * 60 * 60), // Last 7 days
                endTime: Date()
            )
            print("🔄 Background sync tracks (last 7 days): \(backgroundTracks.count)")
            
            // Check local storage
            let localTracks = SpotifyService.shared.getImportedTracksFromLocal()
            print("📱 Local imported tracks: \(localTracks.count)")
            
            print("🔍 ==========================================")
            
        } catch {
            print("❌ Firebase storage check failed: \(error)")
        }
    }
    
    private func loadComprehensiveStats() async {
        guard authViewModel.isUserPermanentlyAuthenticated else {
            print("⚠️ User not authenticated, skipping comprehensive stats")
            return
        }
        
        print("📊 Loading comprehensive track statistics...")
        let stats = await backgroundSync.getComprehensiveTrackStats()
        
        await MainActor.run {
            self.comprehensiveStats = stats
        }
        
        print("📊 Loaded stats: \(stats.displayText)")
    }
    
    // MARK: - UI Components
    
    private var photoLibrarySection: some View {
        HStack {
            Image(systemName: "photo.on.rectangle")
                .foregroundColor(.blue)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("photo library access")
                    .font(.custom("Helvetica Neue", size: 18))
                    .foregroundColor(.primary)
                
                photoStatusText
            }
            
            Spacer()
            
            photoActionButton
        }
        .padding(.vertical, 4)
    }
    
    private var photoStatusText: some View {
        Group {
            switch photoService.authorizationStatus {
            case .authorized:
                Text("full access granted")
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.green)
            case .limited:
                Text("limited access granted")
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.orange)
            case .denied:
                Text("access denied")
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.red)
            case .notDetermined:
                Text("permission needed for photo backgrounds")
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.secondary)
            case .restricted:
                Text("access restricted")
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.red)
            @unknown default:
                Text("unknown status")
                    .font(.custom("Helvetica Neue", size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private var photoActionButton: some View {
        if photoService.authorizationStatus == .notDetermined {
            Button("grant") {
                Task {
                    let _ = await photoService.requestPhotoLibraryAccess()
                }
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.blue)
        } else if photoService.authorizationStatus == .denied {
            Button("settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .font(.custom("Helvetica Neue", size: 12))
            .foregroundColor(.blue)
        } else {
            EmptyView()
        }
    }
    
    private func debugSpotifySync() {
        Task {
            print("🔧 DEBUG: Checking Spotify sync setup...")
            
            // Check Firebase Auth from multiple sources
            print("🔧 Settings UI Firebase authenticated: \(authViewModel.isUserPermanentlyAuthenticated)")
            print("🔧 Settings UI Current user: \(authViewModel.userProfile?.email ?? "nil")")
            print("🔧 Settings UI Current user ID: \(authViewModel.getCurrentUserID() ?? "nil")")
            
            // Check Firebase Auth directly
            let directAuthCheck = Auth.auth().currentUser
            print("🔧 Direct Firebase Auth user: \(directAuthCheck?.email ?? "nil")")
            print("🔧 Direct Firebase Auth UID: \(directAuthCheck?.uid ?? "nil")")
            
            print("🔧 Spotify authenticated: \(spotifyService.isAuthenticated)")
            print("🔧 Background sync status: \(backgroundSync.syncStatus)")
            
            // Check if sync settings exist
            print("🔧 Current sync settings enabled: \(backgroundSync.syncSettings?.isBackgroundSyncEnabled ?? false)")
            
            // Force reload Firebase auth state
            print("🔧 Forcing Firebase auth state reload...")
            print("🔧 Current user ID: \(authViewModel.getCurrentUserID() ?? "nil")")
            
            // Try manual sync
            print("🔧 Attempting manual sync...")
            await SpotifyBackgroundSync.shared.performManualSync()
            
            print("🔧 Final sync status: \(backgroundSync.syncStatus)")
        }
    }
    
    private func testSpotifyAPI() {
        Task {
            await MainActor.run {
                isTestingSpotifyAPI = true
                spotifyTestResult = ""
            }
            
            NSLog("🎵 SPOTIFY API TEST: Starting comprehensive authentication diagnosis...")
            print("🎵 SPOTIFY API TEST: Starting comprehensive authentication diagnosis...")
            
            // ALSO CHECK FIREBASE DATA
            if let userId = authViewModel.getCurrentUserID() {
                print("🔍 ========== FIREBASE DATA CHECK ==========")
                do {
                    // NEW UNIFIED ARCHITECTURE - Check global collection only
                    let globalSnapshot = try await Firestore.firestore()
                        .collection("spotifyListeningHistory")
                        .whereField("userId", isEqualTo: userId)
                        .getDocuments()
                    print("🔍 📊 UNIFIED COLLECTION - spotifyListeningHistory: \(globalSnapshot.documents.count) total")
                    
                    // Check for any remaining legacy data that needs cleanup
                    let legacySnapshot = try await Firestore.firestore()
                        .collection("users").document(userId)
                        .collection("importedSpotifyTracks")
                        .getDocuments()
                    
                    if legacySnapshot.documents.count > 0 {
                        print("⚠️ 📊 LEGACY CLEANUP NEEDED - importedSpotifyTracks: \(legacySnapshot.documents.count) documents (use cleanup button)")
                    } else {
                        print("✅ 📊 LEGACY CLEANUP - No legacy subcollection data found")
                    }
                    
                    let totalTracks = globalSnapshot.documents.count
                    print("🔍 📊 TOTAL TRACKS AVAILABLE: \(totalTracks)")
                    
                    // Quick date range check for unified global collection
                    if !globalSnapshot.documents.isEmpty {
                        let tracks = globalSnapshot.documents.compactMap { doc -> Date? in
                            guard let timestamp = doc.data()["playedAt"] as? Timestamp else { return nil }
                            return timestamp.dateValue()
                        }.sorted()
                        
                        if let earliest = tracks.first, let latest = tracks.last {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "MM/dd/yyyy"
                            print("🔍 📅 UNIFIED COLLECTION Date range: \(formatter.string(from: earliest)) to \(formatter.string(from: latest))")
                        }
                    }
                    
                    // Quick date range check for legacy subcollection
                    if !legacySnapshot.documents.isEmpty {
                        let legacyTracks = legacySnapshot.documents.compactMap { doc -> Date? in
                            guard let timestamp = doc.data()["playedAt"] as? Timestamp else { return nil }
                            return timestamp.dateValue()
                        }.sorted()
                        
                        if let earliest = legacyTracks.first, let latest = legacyTracks.last {
                            let formatter = DateFormatter()
                            formatter.dateFormat = "MM/dd/yyyy"
                            print("🔍 📅 LEGACY COLLECTION Date range: \(formatter.string(from: earliest)) to \(formatter.string(from: latest))")
                        }
                    }
                    
                    // TEST SPECIFIC DATE RANGES (the ones the user mentioned)
                    print("🔍 ========== TESTING SPECIFIC RUN DATES ==========")
                    let testDates = [
                        ("8/23 run", DateComponents(year: 2024, month: 8, day: 23)),
                        ("8/10 run", DateComponents(year: 2024, month: 8, day: 10)),
                        ("8/9 run", DateComponents(year: 2024, month: 8, day: 9)),
                        ("Early August", DateComponents(year: 2024, month: 8, day: 1)),
                        ("Late July", DateComponents(year: 2024, month: 7, day: 25))
                    ]
                    
                    let calendar = Calendar.current
                    for (label, dateComponents) in testDates {
                        guard let targetDate = calendar.date(from: dateComponents) else { continue }
                        
                        let startDate = calendar.startOfDay(for: targetDate)
                        let endDate = calendar.date(byAdding: .day, value: 1, to: startDate)!
                        
                        print("🔍 Testing \(label): \(startDate) to \(endDate)")
                        
                        do {
                            // Test with the new unified query
                            let tracks = try await FirestoreService.shared.getImportedSpotifyTracksForDateRange(
                                userId: userId,
                                startDate: startDate,
                                endDate: endDate
                            )
                            print("🔍 \(label) → Found \(tracks.count) tracks via unified query")
                            
                            // Show first few tracks for verification
                            for (i, track) in tracks.prefix(3).enumerated() {
                                print("🔍   Track \(i+1): \(track.name) by \(track.artist) at \(track.playedAt)")
                            }
                        } catch {
                            print("🔍 \(label) → ERROR: \(error)")
                        }
                    }
                } catch {
                    print("🔍 ❌ Firebase check failed: \(error)")
                }
                print("🔍 ==========================================")
            }
            
            // First, diagnose authentication issues
            let diagnosis = spotifyService.diagnoseAuthenticationIssues()
            NSLog("🔍 Authentication diagnosis: \(diagnosis)")
            print("🔍 Authentication diagnosis: \(diagnosis)")
            print("🔍 User message: \(diagnosis.userMessage)")
            print("🔍 Needs re-authentication: \(diagnosis.needsReAuthentication)")
            
            // Check authentication before token refresh
            NSLog("🎵 Initial Spotify authenticated: \(spotifyService.isAuthenticated)")
            print("🎵 Initial Spotify authenticated: \(spotifyService.isAuthenticated)")
            
            // If we need re-authentication due to missing refresh token, inform user
            if diagnosis == .missingRefreshToken {
                NSLog("🚨 MISSING REFRESH TOKEN DETECTED!")
                print("🚨 MISSING REFRESH TOKEN DETECTED!")
                print("🚨 This is the root cause of sync failures - user must reconnect Spotify")
                print("🚨 Background sync will continue failing until refresh token is restored")
                
                await MainActor.run {
                    spotifyTestResult = "FAILED: Missing refresh token. Need to reconnect Spotify."
                    isTestingSpotifyAPI = false
                }
                return
            }
            
            // CRITICAL: Try to refresh token first
            print("🔐 Testing token refresh mechanism...")
            let refreshSuccess = await spotifyService.refreshTokenIfNeeded()
            print("🔐 Token refresh result: \(refreshSuccess)")
            print("🔐 Post-refresh Spotify authenticated: \(spotifyService.isAuthenticated)")
            
            guard spotifyService.isAuthenticated else {
                NSLog("❌ Spotify not authenticated after refresh attempt - cannot test API")
                print("❌ Spotify not authenticated after refresh attempt - cannot test API")
                print("❌ User needs to reconnect Spotify account to restore refresh token")
                
                await MainActor.run {
                    spotifyTestResult = "FAILED: Not authenticated after refresh. Reconnect needed."
                    isTestingSpotifyAPI = false
                }
                return
            }
            
            await MainActor.run {
                spotifyTestResult = "SUCCESS: Authentication working, checking API..."
            }
            
            // Test time windows
            let now = Date()
            let twoHoursAgo = Calendar.current.date(byAdding: .hour, value: -2, to: now) ?? now
            let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
            
            print("🎵 Testing Spotify API with time windows:")
            print("🎵 Now: \(now)")
            print("🎵 2 hours ago: \(twoHoursAgo)")
            print("🎵 1 day ago: \(oneDayAgo)")
            
            do {
                // Test 1: Last 2 hours
                print("🎵 Test 1: Fetching tracks from last 2 hours...")
                let recentTracks = try await spotifyService.fetchRecentlyPlayed(
                    startTime: twoHoursAgo,
                    endTime: now
                )
                print("🎵 Found \(recentTracks.count) tracks in last 2 hours")
                for (index, track) in recentTracks.prefix(3).enumerated() {
                    print("🎵   \(index + 1). \(track.name) by \(track.artist) at \(track.playedAt)")
                }
                
                // Test 2: Last 24 hours
                print("🎵 Test 2: Fetching tracks from last 24 hours...")
                let dayTracks = try await spotifyService.fetchRecentlyPlayed(
                    startTime: oneDayAgo,
                    endTime: now
                )
                print("🎵 Found \(dayTracks.count) tracks in last 24 hours")
                for (index, track) in dayTracks.prefix(3).enumerated() {
                    print("🎵   \(index + 1). \(track.name) by \(track.artist) at \(track.playedAt)")
                }
                
                if recentTracks.isEmpty && dayTracks.isEmpty {
                    print("⚠️ NO TRACKS FOUND - This explains why sync shows 0 tracks!")
                    print("⚠️ Either you haven't listened to Spotify recently, or there's an API issue")
                    
                    await MainActor.run {
                        spotifyTestResult = "SUCCESS: API working but no recent tracks found"
                        isTestingSpotifyAPI = false
                    }
                } else {
                    await MainActor.run {
                        spotifyTestResult = "SUCCESS: Found \(recentTracks.count + dayTracks.count) tracks total"
                        isTestingSpotifyAPI = false
                    }
                }
                
            } catch {
                NSLog("❌ Spotify API test failed: \(error)")
                print("❌ Spotify API test failed: \(error)")
                print("❌ This explains why background sync isn't working!")
                
                await MainActor.run {
                    spotifyTestResult = "FAILED: API error - \(error.localizedDescription)"
                    isTestingSpotifyAPI = false
                }
            }
        }
    }
    
    private func diagnoseSpotifyAuth() {
        Task {
            print("🔍 SPOTIFY AUTHENTICATION DIAGNOSIS: Starting comprehensive analysis...")
            print("🔍 ================================================")
            
            // Run diagnosis
            let diagnosis = spotifyService.diagnoseAuthenticationIssues()
            print("📋 Diagnosis Result: \(diagnosis)")
            print("📋 User Message: \(diagnosis.userMessage)")
            print("📋 Needs Re-authentication: \(diagnosis.needsReAuthentication)")
            
            // Display diagnosis results based on findings  
            switch diagnosis {
                case .healthy:
                    print("✅ Spotify authentication is healthy!")
                    
                case .notAuthenticated:
                    print("⚪ Spotify not connected - user should connect account")
                    
                case .missingRefreshToken:
                    print("🚨 CRITICAL ISSUE FOUND: Missing refresh token!")
                    print("🚨 This is why background sync shows 0 totalTracksCollected")
                    print("🚨 All API calls will fail with 401 'access token expired' errors")
                    print("🚨 SOLUTION: User must reconnect Spotify to get new refresh token")
                    print("🚨")
                    print("🚨 Forcing re-authentication to fix this issue...")
                    
                    // Force re-authentication to solve the problem
                    spotifyService.forceReAuthentication()
                    print("✅ Forced re-authentication complete - UI should now show 'connect' button")
                    
                case .tokenExpired:
                    print("⚠️ Token expired but refresh available - attempting refresh...")
                    let success = await spotifyService.refreshTokenIfNeeded()
                    print("🔄 Refresh attempt result: \(success)")
            }
            
            print("🔍 ================================================")
            print("🔍 DIAGNOSIS COMPLETE")
        }
    }
    
    private func testManualSync() {
        print("🧪 ========== MANUAL SYNC TEST ==========")
        Task {
            print("🧪 Starting manual sync test...")
            await backgroundSync.performManualSync()
            print("🧪 Manual sync test completed")
            print("🧪 Check console for detailed logs")
            print("🧪 =====================================")
        }
    }
    
    private func debugFirebaseData() {
        print("🔍 ========== FIREBASE DEBUG ==========")
        Task {
            guard let userId = authViewModel.getCurrentUserID() else {
                print("🔍 No user ID available")
                return
            }
            
            // Check total count in Firebase collections
            do {
                // Check importedSpotifyTracks subcollection
                let importedSnapshot = try await Firestore.firestore()
                    .collection("users").document(userId)
                    .collection("importedSpotifyTracks")
                    .getDocuments()
                print("🔍 📊 IMPORTED TRACKS in Firebase: \(importedSnapshot.documents.count) total documents")
                
                // Check spotifyListeningHistory collection
                let listeningSnapshot = try await Firestore.firestore()
                    .collection("spotifyListeningHistory")
                    .whereField("userId", isEqualTo: userId)
                    .getDocuments()
                print("🔍 📊 LISTENING HISTORY in Firebase: \(listeningSnapshot.documents.count) total documents")
                
                // Get date range of tracks in Firebase
                if !importedSnapshot.documents.isEmpty {
                    let tracks = importedSnapshot.documents.compactMap { doc -> Date? in
                        guard let timestamp = doc.data()["playedAt"] as? Timestamp else { return nil }
                        return timestamp.dateValue()
                    }.sorted()
                    
                    if let earliest = tracks.first, let latest = tracks.last {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "MM/dd/yyyy HH:mm"
                        print("🔍 📅 Date range: \(formatter.string(from: earliest)) to \(formatter.string(from: latest))")
                    }
                }
                
                // Sample tracks from different time periods
                let calendar = Calendar.current
                let now = Date()
                
                // Check specific date ranges
                print("\n🔍 Checking specific date ranges:")
                
                // 8/23 run (recent)
                if let aug23 = calendar.date(from: DateComponents(year: 2024, month: 8, day: 23)) {
                    let aug23End = calendar.date(byAdding: .hour, value: 1, to: aug23) ?? aug23
                    let aug23Tracks = await spotifyService.fetchImportedTracksForTimeRange(startTime: aug23, endTime: aug23End)
                    print("🔍 8/23 (1 hour): \(aug23Tracks.count) tracks")
                    
                    for track in aug23Tracks.prefix(3) {
                        print("🔍   - \(track.name) by \(track.artist)")
                        print("🔍     Album art: \(track.albumImageURL != nil ? "✅" : "❌")")
                    }
                }
                
                // Early August
                if let earlyAug = calendar.date(from: DateComponents(year: 2024, month: 8, day: 10)) {
                    let earlyAugEnd = calendar.date(byAdding: .hour, value: 4, to: earlyAug) ?? earlyAug
                    let earlyAugTracks = await spotifyService.fetchImportedTracksForTimeRange(startTime: earlyAug, endTime: earlyAugEnd)
                    print("🔍 8/10 (4 hours): \(earlyAugTracks.count) tracks")
                }
                
                // Late July
                if let lateJuly = calendar.date(from: DateComponents(year: 2024, month: 7, day: 25)) {
                    let lateJulyEnd = calendar.date(byAdding: .hour, value: 4, to: lateJuly) ?? lateJuly
                    let lateJulyTracks = await spotifyService.fetchImportedTracksForTimeRange(startTime: lateJuly, endTime: lateJulyEnd)
                    print("🔍 7/25 (4 hours): \(lateJulyTracks.count) tracks")
                }
                
                // June 29 (when import started)
                if let june29 = calendar.date(from: DateComponents(year: 2024, month: 6, day: 29)) {
                    let june29End = calendar.date(byAdding: .hour, value: 4, to: june29) ?? june29
                    let june29Tracks = await spotifyService.fetchImportedTracksForTimeRange(startTime: june29, endTime: june29End)
                    print("🔍 6/29 (4 hours): \(june29Tracks.count) tracks")
                }
                
            } catch {
                print("🔍 ❌ Error checking Firebase: \(error)")
            }
            
            print("🔍 =====================================")
        }
    }
}

*/

#Preview {
    SettingsView()
}