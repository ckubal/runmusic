import Foundation
import FirebaseAuth
import GoogleSignIn
import FirebaseCore

@MainActor
class FirebaseAuthService: ObservableObject {
    static let shared = FirebaseAuthService()
    
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var userProfile: UserProfile?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var authStateListener: AuthStateDidChangeListenerHandle?
    
    init() {
        setupAuthListener()
    }
    
    deinit {
        if let listener = authStateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    private func setupAuthListener() {
        authStateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                
                // If user is authenticated (including on app startup with existing login),
                // sync service tokens to restore connections
                if let user = user {
                    await self?.syncServiceTokens()
                    await self?.loadUserProfile(userId: user.uid)
                } else {
                    self?.userProfile = nil
                }
            }
        }
    }
    
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let windowScene = await UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = await windowScene.windows.first,
                  let rootViewController = await window.rootViewController else {
                throw FirebaseAuthError.noRootViewController
            }
            
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw FirebaseAuthError.noClientID
            }
            
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            
            guard let idToken = result.user.idToken?.tokenString else {
                throw FirebaseAuthError.noIDToken
            }
            
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            let authResult = try await Auth.auth().signIn(with: credential)
            
            await createUserProfileIfNeeded(user: authResult.user)
            
            // Sync service tokens after successful sign-in
            await syncServiceTokens()
            
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func signOut() async {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func createUserProfileIfNeeded(user: User) async {
        let firestoreService = FirestoreService.shared
        
        do {
            let profileExists = try await firestoreService.userProfileExists(userId: user.uid)
            
            if !profileExists {
                var userProfile = UserProfile(
                    id: user.uid,
                    email: user.email ?? "",
                    displayName: user.displayName ?? "",
                    photoURL: user.photoURL?.absoluteString,
                    createdAt: Date(),
                    lastActiveAt: Date(),
                    preferences: UserPreferences.shared.exportToFirebase(),
                    stravaUserId: nil,
                    username: nil
                )
                
                // Add Strava user ID if available
                if StravaService.shared.isAuthenticated, let stravaId = StravaService.shared.athlete?.id {
                    userProfile.stravaUserId = String(stravaId)
                }
                
                try await firestoreService.createUserProfile(userProfile)
            } else {
                try await firestoreService.updateLastActive(userId: user.uid)
            }
        } catch {
            print("Error creating/updating user profile: \(error)")
        }
    }
    
    private func syncServiceTokens() async {
        guard let user = currentUser else {
            print("❌ FirebaseAuthService: No current user for token sync")
            return
        }
        
        // Sync Spotify and Strava tokens from Firebase when user signs in
        print("🔄 FirebaseAuthService: Starting service token sync for user \(user.uid)")
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await SpotifyService.shared.syncWithFirebase()
            }
            
            group.addTask {
                await StravaService.shared.syncWithFirebase()
            }
            
            // CRITICAL FIX: Also upload any local tokens that weren't uploaded before
            group.addTask {
                await StravaService.shared.uploadLocalTokensIfFirebaseAvailable()
            }
        }
        
        print("✅ FirebaseAuthService: Service token sync completed")
        
        // Log the final authentication status
        let spotifyAuth = await SpotifyService.shared.isAuthenticated
        let stravaAuth = await StravaService.shared.isAuthenticated
        print("🔐 Auth Status - Spotify: \(spotifyAuth), Strava: \(stravaAuth)")
    }
    
    func updateUsername(_ username: String) async throws {
        guard let user = currentUser else {
            throw FirebaseAuthError.noUser
        }
        
        // Update user profile with username
        try await FirestoreService.shared.updateUserProfile(UserProfile(
            id: user.uid,
            email: user.email ?? "",
            displayName: user.displayName ?? "",
            photoURL: user.photoURL?.absoluteString,
            createdAt: Date(), // This will be ignored in merge update
            lastActiveAt: Date(),
            preferences: UserPreferences.shared.exportToFirebase(),
            stravaUserId: StravaService.shared.athlete?.id != nil ? String(StravaService.shared.athlete!.id) : nil,
            username: username
        ))
        
        print("✅ Username updated successfully: @\(username)")
        
        // Reload user profile to reflect changes
        await loadUserProfile(userId: user.uid)
    }
    
    func loadUserProfile(userId: String) async {
        do {
            let profile = try await FirestoreService.shared.getUserProfile(userId: userId)
            await MainActor.run {
                self.userProfile = profile
            }
        } catch {
            print("Failed to load user profile: \(error)")
            await MainActor.run {
                self.userProfile = nil
            }
        }
    }
}

enum FirebaseAuthError: LocalizedError {
    case noRootViewController
    case noClientID
    case noIDToken
    case noUser
    
    var errorDescription: String? {
        switch self {
        case .noRootViewController:
            return "Unable to find root view controller"
        case .noClientID:
            return "No client ID found in Firebase configuration"
        case .noIDToken:
            return "Failed to get ID token from Google Sign-In"
        case .noUser:
            return "No authenticated user found"
        }
    }
}